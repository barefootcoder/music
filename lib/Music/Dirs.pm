package Music::Dirs;

use myperl;

use base 'Exporter';
our @EXPORT =
(
	qw< $MUSICHOME $ALBUM_DIR $MISC_DIR $SINGLES_DIR $XMAS_DIR $TRACKLIST_DIR >,
	qw< is_album_dir is_tracklist album_dirs track_dirs all_albums >
);


const our $MUSICHOME => dir($ENV{'MUSICHOME'});
const our $ALBUM_DIR => $MUSICHOME->subdir('Albums');
const our $MISC_DIR => $MUSICHOME->subdir('Misc');
const our $SINGLES_DIR => $MUSICHOME->subdir('Singles');
const our $XMAS_DIR => $MUSICHOME->subdir('xmas');
const our $TRACKLIST_DIR => $MUSICHOME->subdir('tracklists');


func is_album_dir ($dir)
{
	return -d $dir and ($ALBUM_DIR->resolve->contains($dir) or $MISC_DIR->resolve->contains($dir));
}

func is_tracklist ($file)
{
	return -f $file and $file =~ /\.m3u$/ and $TRACKLIST_DIR->resolve->contains($file);
}


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
