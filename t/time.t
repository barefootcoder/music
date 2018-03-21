use 5.14.2;
use Test::Most;
use autodie ':all';
BEGIN { die("MUSICHOME must be set!") unless $ENV{MUSICHOME} }

use Music::Time;


my %TO_CASES =
(
	'10:10'	=>	610,
	'01:01'	=>	61,
	'1:01'	=>	61,
	'1:1'	=>	61,
	'100:0'	=>	6000,
);

foreach (keys %TO_CASES)
{
	is to_seconds($_), $TO_CASES{$_}, "successful conversion to seconds for $_";
}


my %FROM_CASES =
(
	610		=>	'10:10',
	61		=>	'1:01',
	6000	=>	'100:00',
);

foreach (keys %FROM_CASES)
{
	is to_time($_), $FROM_CASES{$_}, "successful conversion from seconds for $_";
}


my @CMP_CASES =
(
	[ '2:33', '2:33' =>  0 ],
	[ '2:33', '2:34' =>  0 ],
	[ '2:33', '2:32' =>  0 ],
	[ '2:34', '2:33' =>  0 ],
	[ '2:32', '2:33' =>  0 ],
	[ '2:33', '3:33' => -1 ],
	[ '2:33', '2:43' => -1 ],
	[ '2:33', '2:35' => -1 ],
	[ '3:33', '2:33' =>  1 ],
	[ '2:43', '2:33' =>  1 ],
	[ '2:35', '2:33' =>  1 ],
);

foreach (@CMP_CASES)
{
	my ($lhs, $rhs, $res) = @$_;
	is compare_times($lhs, $rhs), $res, "successful comparison for $lhs <=> $rhs";
}


done_testing;
