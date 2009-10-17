use inc::Module::Install;
name 'Sledge-PSGI';
all_from 'lib/Sledge/PSGI.pm';

# requires '';

tests 't/*.t';
author_tests 'xt';

build_requires 'Test::More';
use_test_base;
auto_include;
WriteAll;
