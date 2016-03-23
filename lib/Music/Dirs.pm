package Music::Dirs;

use myperl;

use base 'Exporter';
our @EXPORT =
(
	qw< $MUSICHOME $ALBUM_DIR $MISC_DIR $SINGLES_DIR $XMAS_DIR $TRACKLIST_DIR $DROPBOX_DIR >,
	qw< album_dirs track_dirs all_albums >
);


const our $MUSICHOME => dir($ENV{'MUSICHOME'});
const our $ALBUM_DIR => $MUSICHOME->subdir('Albums');
const our $MISC_DIR => $MUSICHOME->subdir('Misc');
const our $SINGLES_DIR => $MUSICHOME->subdir('Singles');
const our $XMAS_DIR => $MUSICHOME->subdir('xmas');
const our $TRACKLIST_DIR => $MUSICHOME->subdir('tracklists');
const our $DROPBOX_DIR => dir(<~buddy>, 'Dropbox', 'music');


func album_dirs ()
{
	return ($ALBUM_DIR, $MISC_DIR);
}

func track_dirs ()
{
	return (album_dirs, $SINGLES_DIR, $XMAS_DIR);
}

func all_albums ()
{
	return map { $_->children } album_dirs;
}



1;
