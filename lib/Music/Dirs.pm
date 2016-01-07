package Music::Dirs;

use myperl;

use base 'Exporter';
our @EXPORT = qw< $MUSICHOME $ALBUM_DIR $MISC_DIR $SINGLES_DIR $TRACKLIST_DIR $DROPBOX_DIR track_dirs >;


const our $MUSICHOME => dir($ENV{'MUSICHOME'});
const our $ALBUM_DIR => $MUSICHOME->subdir('Albums');
const our $MISC_DIR => $MUSICHOME->subdir('Misc');
const our $SINGLES_DIR => $MUSICHOME->subdir('Singles');
const our $TRACKLIST_DIR => $MUSICHOME->subdir('tracklists');
const our $DROPBOX_DIR => dir(<~buddy>, 'Dropbox', 'music');


func track_dirs ()
{
	return ($ALBUM_DIR, $SINGLES_DIR);
}



1;
