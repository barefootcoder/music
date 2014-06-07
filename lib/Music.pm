package Music;

use myperl;

use Cwd;
use Carp;
use MP3::Tag;
use File::Spec;
use File::Find;
use File::HomeDir;
use File::Basename;
use Text::Capitalize;

use base 'Exporter';
our @EXPORT = qw<
	$ME $MUSICHOME $ALBUM_DIR $SINGLES_DIR $TRACKLIST_DIR $DROPBOX_DIR usage_error fatal_error album_arg
	album title filename alpha_filename track_dirs sort_tracklist generate_tracklist rename_album
	get_track_info
	attach_album_art extract_album_art
	rebuild_playlists tracklist_file find_tracklists_containing cover_file realpath
>;


const our $ME => file($0)->basename;
const our $MUSICHOME => dir($ENV{'MUSICHOME'});
const our $ALBUM_DIR => $MUSICHOME->subdir('Albums');
const our $SINGLES_DIR => $MUSICHOME->subdir('Singles');
const our $TRACKLIST_DIR => $MUSICHOME->subdir('tracklists');
const our $DROPBOX_DIR => dir(<~buddy>, 'Dropbox', 'music');


func get_tag ($file)
{
	my $tag = MP3::Tag->new($file);
	croak("couldn't get tag for $file [$!]") unless $tag;

	$tag->get_tags;
	$tag->config( write_v24 => 1 );
	return $tag;
}


func fatal_error (@msgs)
{
	say STDERR "$ME: $_" foreach @msgs;
	exit 1;
}

func usage_error ($msg)
{
	say STDERR "$ME: $msg (`$ME -h' for help, if you're lucky)";
	exit 2;
}


func album_arg ($arg)
{
	use Tie::IxHash;

	tie my %typedirs, 'Tie::IxHash',
	(
		tracklist	=>	$TRACKLIST_DIR->absolute->resolve,
		album		=>	$ALBUM_DIR->absolute->resolve,
		base		=>	$MUSICHOME->absolute->resolve,
		Dropbox		=>	$DROPBOX_DIR->absolute->resolve,
	);


	# normalize argument
	my $argtype;
	usage_error("must supply argument to operate on") unless $arg;
	debuggit(2 => "album_arg argument is", $arg);

	$arg = file($arg)->absolute->resolve;
	usage_error("can't read the file: $arg") unless -r $arg;

	foreach (keys %typedirs)
	{
		my $dir = $typedirs{$_};
		if ($typedirs{$_}->contains($arg))
		{
			my $album = $arg->basename;
			$album =~ s/\.m3u$//;
			return wantarray ? ($album, $_) : $album;
		}
	}

	fatal_error("I have no idea what '$1' is");
}


func album ($type, $album)
{
	given ($type)
	{
		return $ALBUM_DIR->subdir($album)							when 'dir';
		return $TRACKLIST_DIR->file('Albums', "$album.m3u")			when 'tracklist';
		when ('cover')
		{
			my $cover = capitalize($album);
			$cover = join('-', map { s/\W//g; $_ } split(' - ', $cover));
			return $MUSICHOME->file('covers', "$cover.jpg");
		}

		default { usage_error("illegal type $type to album()") }
	}
}


func track_dirs ()
{
	return ($ALBUM_DIR, $SINGLES_DIR);
}


# DEPRECATED! switch to Path::Class style instead
sub realpath
{
	warn("this function is deprecated and will be removed in a future version");

	# similar to Cwd::realpath, only works for files as well as dirs
	my ($vol, $dir, $file) = File::Spec->splitpath(File::Spec->rel2abs($_[0]));
	my $realpath = Cwd::realpath(File::Spec->catpath($vol, $dir));
	return File::Spec->catfile($realpath, $file);
}


# given a title (album, artist, or song), consistencize it as regards
#	*	capitalization
#	*	whitespace
func _titlecase ($title)
{
	# a few extensions on the standard title_case
	my $title_split = qr{\s*/\s*};
	$title = join('', map { /$title_split/ ? $_ : title_case($_) } split(/($title_split)/, $title));
	$title =~ s/ & His / & his /;
	$title =~ s/ (Vs[.]?) /\L $1 /;
	return $title;
}
func title (@titles)
{
	return wantarray ? map { _titlecase($_) } @titles : _titlecase($titles[0]);
}


# turn a potential filename (or dirname) into a valid one by:
#	*	changing any /'s into \'s
#	*	turning any international characters into their Latin equivalents
func filename ($title)
{
	use Text::Unidecode;

	$title =~ s{/}{|}g;
	return unidecode($title);
}

# slight variation on filename(), generally used for albums:
#	*	all the same stuff as above, plus
#	*	remove any leading "The", so they'll sort correctly
#	*	invert artist name ("Joe Blow" into "Blow, Joe"), but *only* if requested
func alpha_filename ($album, :$invert = 0)
{
	$album = filename($album);
	$album =~ s/^the //i;
	$album =~ s/^(.+?) (\S+?) - /$2, $1 - / if $invert;
	return $album;
}


func sort_tracklist (@tracks)
{
	my %schwartzian;
	foreach (@tracks)
	{
		my $tag = get_tag($_);
		my $tracknum = $tag->track1 || 0;
		my $discnum = $tag->disk1 || 0;
		my $year = $tag->year || 0;
		$schwartzian{$_} = sprintf("%04d%s%02d%02d", $year, $tag->album, $discnum, $tracknum);
	}
	return sort { $schwartzian{$a} cmp $schwartzian{$b} } keys %schwartzian;
}

func generate_tracklist ($album)
{
	my $albumdir = album(dir => $album);

	my @tracks = sort_tracklist grep { -f } $albumdir->children();

	my $tracklist_file = album(tracklist => $album);
	open(OUT, ">$tracklist_file") or die("can't open tracklist file: $tracklist_file");
	say OUT $_ foreach @tracks;
	close(OUT);
}


func rename_album ($old, $new)
{
	die("can't find existing album $old") unless -d $ALBUM_DIR->file($old);
	die("new name $new already exists") if -e $ALBUM_DIR->file($new);

	rename $ALBUM_DIR->file($old), $ALBUM_DIR->file($new);

	# fix tracklist
	my $old_tl = album(tracklist => $old);
	my $new_tl = album(tracklist => $new);
	fix_tracklist($old_tl, $old, $new);
	rename $old_tl, $new_tl;

	# fix cover file (if it exists)
	my $old_cover = album(cover => $old);
	my $new_cover = album(cover => $new);
	debuggit(2 => "trying to rename", $old_cover, "to", $new_cover,
			"and old cover", -e $old_cover ? "does" : "does not", "exist");
	rename $old_cover, $new_cover if -e $old_cover;

	# fix any mentions in other tracklists
	foreach my $tl (find_tracklists_containing($old, qr{[^/]+}))
	{
		fix_tracklist($tl, $old, $new);
	}

	# always rebuild at the end
	rebuild_playlists();
}


func _generate_track_key ($new_track, $existing_tracks)
{
	my @clashes = grep { my $l = substr($_,0,1); $new_track =~ /^$l/i } keys %$existing_tracks;
	if (@clashes)
	{
		my $maxlen = 0;
		foreach my $clash (grep { my $l = substr($_,0,1); $new_track =~ /^$l/i } keys %$existing_tracks)
		{
			# so figure out how long a prefix we need not to clash any more
			my $len = 1;
			++$len while lc substr($new_track, 0, $len) eq lc substr($existing_tracks->{$clash}, 0, $len);
			# out with the old, in with the new
			# but only if the new length is _bigger_ than the old one
			if ($len > length($clash))
			{
				my $prefix = substr($existing_tracks->{$clash}, 0, $len);
				$existing_tracks->{$prefix} = delete $existing_tracks->{$clash};
			}

			# length of prefix for the new track is the longest length we find here
			$maxlen = max($maxlen, $len);
		}

		# now add the new track (shouldn't clash any more)
		my $prefix = substr($new_track, 0, $maxlen);
		die("something went very very wrong: $prefix => $existing_tracks->{$prefix}") if exists $existing_tracks->{$prefix};
		$existing_tracks->{$prefix} = $new_track;
	}
	else
	{
		# just jam it in there with one letter
		my $prefix = substr($new_track, 0, 1);
		$existing_tracks->{$prefix} = $new_track;
	}
	debuggit(4 => "after processing, struct is", DUMP => $existing_tracks);
}

func get_track_info ($url)
{
	use WWW::Mechanize;

	my $m = WWW::Mechanize->new;
	$m->get($url);
	my $doc = $m->content();
	($doc) = $doc =~ m{\bid\s*=\s*"?Track_listing\b(.*?)</(table|ol)>}s;
	$doc =~ s{<.*?>}{}sg;
	debuggit(4 => "doc is", $doc);

	my @tracks = $doc =~ m{"(.*?)"}g;
	debuggit(4 => "got tracks:", DUMP => \@tracks);

	# create hash of title => track
	# also, look for duplicate track names
	my $track_info = {};
	my %dups;
	foreach (keys @tracks)
	{
		my $track = $tracks[$_];
		if (exists $dups{$track})
		{
			if ($dups{$track} == 1)
			{
				my $first_num = delete $track_info->{$track};
				my $first_track = $track . " [1]";
				$track_info->{$first_track} = $first_num;
			}
			my $which = ++$dups{$track};
			$track .= " [$which]";
		}
		else
		{
			$dups{$track} = 1;
		}
		$track_info->{$track} = $_ + 1;				# convert from 0-based to 1-based
	}
	debuggit(6 => "track dups:", DUMP => \%dups);
	debuggit(3 => "track info:", DUMP => $track_info);

	return $track_info;
}


func attach_album_art ($track, $image)
{
	my $tag = $track->isa('MP3::Tag') ? $track : get_tag($track);
	die("no ID3v2 tag to attach album art to") unless $tag->{'ID3v2'};
	$tag->{'ID3v2'}->add_frame('APIC', chr(0), 'image/jpeg', chr(3), 'Cover Art', $image);
	$tag->update_tags({}, 1);
}

func extract_album_art ($track)
{
	my $tag = $track->isa('MP3::Tag') ? $track : get_tag($track);
	debuggit(4 => "tag is", DUMP => $tag);

	return undef unless defined $tag->{'ID3v2'};
	return undef unless defined $tag->{'ID3v2'}->get_frame('APIC');
	return $tag->{'ID3v2'}->get_frame('APIC')->{'_Data'};
}


func fix_tracklist ($filename, $old_album, $new_album)
{
	my @tracks =
		map { my $i = index($_, $old_album); substr($_, $i, length($old_album)) = $new_album unless $i == -1; $_ }
		slurp "$filename";
	open(OUT, ">$filename") and print OUT @tracks and close(OUT);
}


sub rebuild_playlists
{
	my $basedir = "$TRACKLIST_DIR";
	my $gqdir = (getpwnam($ENV{'USER'}))[7] . "/.gqmpeg/playlists";
	return unless -d $gqdir;

	# out with the old ...
	system("rm -rf $gqdir/*");

	# ... and in with the new
	my $sub = sub
	{
		my $newfile = $File::Find::name;
		$newfile =~ s@$basedir@$gqdir@;
		$newfile =~ s@\.m3u@.gqmpeg@;

		if (-d)
		{
			mkdir $newfile unless -d $newfile;
		}
		else
		{
			#print "ln -s '$File::Find::name' '$newfile'\n";
			system(qq{ln -s "$File::Find::name" "$newfile"});
		}
	};

	find($sub, $basedir);
}


# DEPRECATED! switch to album(tracklist => $album) style instead
sub tracklist_file
{
	warn("this function is deprecated and will be removed in a future version");
	my ($album_dir) = @_;

	my ($vol, $dirs) = File::Spec->splitpath($album_dir, 1);
	my @dirs = File::Spec->splitdir($dirs);

	my $file = pop @dirs;
	$file .= '.m3u';

	splice @dirs, -1, 0, 'tracklists';
	$dirs = File::Spec->catdir(@dirs);
	return File::Spec->catpath($vol, $dirs, $file);
}


sub find_tracklists_containing
{
	my ($album, $song) = @_;

	my @results;
	foreach my $tl (`find $TRACKLIST_DIR -type f -name "*.m3u"`)
	{
		chomp $tl;
		my $regex = qr{ $album/$song $ }x;
		debuggit(4 => "checking file", $tl, "for", $regex);

		push @results, $tl if grep { m{$album/$song$} } slurp $tl;
	}

	return @results;
}


sub cover_file
{
	my ($album_dir, $ext) = @_;

	my ($vol, $dirs) = File::Spec->splitpath($album_dir, 1);
	my @dirs = File::Spec->splitdir($dirs);

	my $file = pop @dirs;
	$file = join('', map { ucfirst } split(/ +/, $file));
	$file .= $ext;

	splice @dirs, -1, 1, 'covers';
	$dirs = File::Spec->catdir(@dirs);
	return File::Spec->catpath($vol, $dirs, $file);
}



#############################
## CLASSES
#############################


class MixTrack
{
	has artist			=>	( ro, isa => Str );
	has title			=>	( ro, isa => Str );
	#has list_status		=>	( ro, isa => enum([qw< added to_add to_find >]) );
	#has seq_status		=>	( ro, isa => enum([qw< leader solid iffy unknown wrong >]) );
	#has track_status	=>	( ro, isa => enum([qw< solid bridge title iffy >]) );
	# pseudo-attributes
	has filename	=>	( ro, lazy_build );

	# builders
	around BUILDARGS ($class: @_)
	{
		state $list_statuses =	{ ' ' => 'added', '>' => 'to_add', 'F' => 'to_find' };
		state $seq_statuses =	{ '*' => 'leader', '>' => 'solid', '~' => 'iffy', '?' => 'unknown', 'X' => 'wrong' };
		state $track_statuses =	{ ':' => 'solid', 'V' => 'bridge', '=' => 'title', '?' => 'iffy' };

		if (@_ == 1)
		{
			my ($list, $seq, $track) = qw< added unknown iffy >;		# default values for statuses
			if ( /^(.)(.)(.)\s\S/ )
			{
				$list = $list_statuses->{$1};
				$seq = $seq_statuses->{$2};
				$track = $track_statuses->{$3};
				$_ = substr($_, 4);
			}
			else
			{
				s/^\s+//;
			}
			/^(.*?) - (.*)$/;
			return $class->$orig(
					artist			=>	$2,
					title			=>	$1,
					list_status		=>	$list,
					seq_status		=>	$seq,
					track_status	=>	$track
			);
		}
		return $class->$orig(@_);
	}

	method _build_filename
	{
		use File::Glob 'bsd_glob';

		#my $basename = "$artist - $title.mp3";
		#my $filename = bsd_glob($ALBUM_DIR->subdir($self->artist . " - *")->file($basename))
		#		|| bsd_glob($SINGLES_DIR->file($basename)) || die("can't locate track $basename");
		#return $filename;
	}
}

class Mixes
{
	use MooseX::Singleton;

	has tracks	=>	( ro, isa => 'ArrayRef[MixTrack]', lazy_build );

	# builders
	method _build_tracks
	{
		my $prev;
		foreach ($MUSICHOME->file('mixes')->slurp(chomp => 1))
		{
			$prev = $_, next unless defined $_;

			if ( /^=+$/ )
			{
			}
		}
	}
}



1;
