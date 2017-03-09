use 5.14.2;
use Test::Most;
use autodie ':all';
BEGIN { die("MUSICHOME must be set!") unless $ENV{MUSICHOME} }

use Path::Class;

use Music;
use Music::Dirs;


my $orig_home = "$MUSICHOME";
my $real_home = dir($MUSICHOME)->resolve;
mpath("foo");
is $MUSICHOME, $orig_home, "MUSICHOME survives immutability test";


is mpath($0), undef, "mpath rejects real paths not under MUSICHOME";
is mpath("/foo"), undef, "mpath rejects notional paths not under MUSICHOME";

my $test_file = "$MUSICHOME/foo";
is mpath($test_file), "$MUSICHOME/foo", "mpath deals with absolute unresolved notional paths";
$test_file = "$real_home/foo";
is mpath($test_file), "$MUSICHOME/foo", "mpath deals with absolute resolved notional paths";

chdir $SINGLES_DIR;
$test_file = (glob("*"))[0];
is mpath($test_file), "$MUSICHOME/Singles/$test_file", "mpath handles relative/absolute correctly";

chdir $ALBUM_DIR;
my $test_dir = (glob("*"))[0];
is mpath($test_dir), "$MUSICHOME/Albums/$test_dir", "mpath deals with relative real paths";
is mpath("$ALBUM_DIR/$test_dir"), "$MUSICHOME/Albums/$test_dir", "mpath deals with absolute real paths";


done_testing;
