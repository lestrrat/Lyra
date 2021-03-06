package Lyra::Server::Click;
use Moose;
use AnyEvent;
use Lyra::Extlib;
use URI;
use namespace::autoclean;

with qw(
    Lyra::Trait::WithMemcached
    Lyra::Trait::WithDBI
    Lyra::Trait::AsyncPsgiApp
);

has ad_id_query_key => (
    is => 'ro',
    isa => 'Str',
    default => 'ad',
);

has log_storage => (
    is => 'ro',
    handles => {
        log_click => 'store',
    },
);

sub process {
    my ($self, $start_response, $env) = @_;

    # Stuff that gets logged at the end goes here
    my %log_info = (
        remote_addr => $env->{REMOTE_ADDR},
        query       => $env->{QUERY_STRING},
    );

    # This is the CV that gets called at the end
    my $cv = AE::cv {
        my ($status, $header, $content) = $_[0]->recv;
        respond_cb($start_response, $status, $header, $content);
        if ($status eq 302) { # which is success for us
            $self->log_click( \%log_info );
        }
        undef %log_info;
        undef $status;
        undef $header;
        undef $content;
    };

    # check for some conditions
    my ($status, @headers, $content);

    if ($env->{REQUEST_METHOD} ne 'GET') {
        $cv->send( 400 );
        return;
    }

    # if we got here, then we're just going to redirect to the
    # landing page. 
    my %query = URI->new('http://dummy/?' . ($env->{QUERY_STRING} || ''))->query_form;

    my $ad_id = $query{ $self->ad_id_query_key };

    $self->load_ad( $ad_id, $cv );
}

sub _load_ad_from_memd_cb {
    my ($self, $final_cv, $ad_id, $ad) = @_;

    if ($ad) {
        $final_cv->send( 302, [ Location => $ad->[0] ] );
    } else {
        $self->load_ad_from_db( $final_cv, $ad_id );
    }
}

sub _load_ad_from_db_cb {
    my ($self, $final_cv, $ad_id, $rows) = @_;
    if (! defined $rows) {
        confess "PANIC: loading from DB returned undef";
    }

    if (@$rows > 0) {
        $self->cache->set( $ad_id, $rows->[0], \&Lyra::_NOOP );

        $final_cv->send( 302, [ Location => $rows->[0]->[0] ] );
    } else {
        $final_cv->send( 404 );
    }
}

# Ad retrieval. Try memcached, if you failed, load from DB
*load_ad = \&load_ad_from_memd;

sub load_ad_from_memd {
    my ($self, $ad_id, $final_cv) = @_;
    $self->cache->get( $ad_id, sub { _load_ad_from_memd_cb( $self, $final_cv, $ad_id, @_ ) } );
}

sub load_ad_from_db {
    my ($self, $final_cv, $ad_id) = @_;

    $self->execsql(
        "SELECT landing_uri FROM lyra_ads_master WHERE id = ?",
        $ad_id,
        sub { _load_ad_from_db_cb( $self, $final_cv, $ad_id, $_[1] ) }
    );
}

1;
