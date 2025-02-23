use v5.36;

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

	subtest 'new' => sub {
		my $constructor_method = 'new';
		my @categories = $class->$method();

		foreach my $category ( @categories ) {
			can_ok $category, $constructor_method;
			}
		};
	};

subtest 'parse message' => sub {
	state $method = '_parse_log_line';

	my $log_line = '2023-01-31 17:01:50.0137 [555] paused:688: Info: Requesting a GET on uri [file://data/pause/incoming/Foo-Bar-1.37.tar.gz]';
	my $type = 'get';

	can_ok $class, $method;
	my $result = $class->$method( $log_line );
	isa_ok $result, $class . '::Line';

	my $type_method = "is_$type";
	can_ok $result, $type_method;
	ok $result->$type_method(), "line is a $type" or diag $log_line;
	ok ! $result->is_unknown, 'line is not unknown' or diag $log_line;

	foreach my $category ( $class->categories ) {
		$category =~ s/.*:://;
		next if $category eq $type;

		$type_method = "is_$category";
		can_ok $result, $type_method;
		ok ! $result->$type_method(), "line is not a $category";
		}

	};

done_testing();
