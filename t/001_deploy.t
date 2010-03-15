use strict;
use Test::More tests => 2;

use_ok "App::Lyra::DeployDB";

eval {
    App::Lyra::DeployDB->new(
        dsn => $ENV{TEST_DSN},
        data_source => 't::Lyra::Test::Fixture::TestDB',
    )->run();
};
ok(! $@, "Done deploy") or diag($@);
