use Test::More;

my $class = 'PAUSEx::Log';

subtest 'sanity' => sub {
	use_ok $class;
	};

subtest 'categories' => sub {
	my $method = 'categories';

	my $prefix = 'PAUSEx::Log::';

	subtest 'wantarray' => sub {
		my @categories = $class->$method();
		cmp_ok scalar @categories, '>', 1, 'there are multiple categories';
		ok ! ref $categories[0], 'first item is not a reference';

		my $not = grep { ! /\A \Q$prefix\E /x } @categories;
		is $not, 0, "All entries start with $prefix";
		};

	subtest 'scalar context' => sub {
		my $categories = $class->$method();
		isa_ok $categories, ref [];

		my $not = grep { ! /\A \Q$prefix\E /x } @$categories;
		is $not, 0, "All entries start with $prefix";
		};

	};

done_testing();
