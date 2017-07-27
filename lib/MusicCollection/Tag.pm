use myperl;


class MusicCollection::Tag
{
	use Carp;
	use MP3::Tag;
	use MP3::Info;
	$MP3::Info::try_harder = 1;

	use Music::Dirs;


	# ATTRIBUTES
	has file		=>	( ro, isa => 'Path::Class::File', lazy, builder => '_get_sample_file' );
	has dir			=>	( ro, isa => 'Path::Class::Dir', predicate => 'is_album' );
	has _tag		=>	( rw, isa => 'MP3::Tag', lazy, builder => '_get_tag',
								handles =>	{
												tracknum => 'track1', discnum => 'disk1',
												map { $_ => $_ }
													qw< config artist title album year genre comment >,
													qw< artist_set title_set album_set year_set genre_set track_set >,
													qw< comment_set >,
											},
						);
	has _info		=>	( rw, isa => 'MP3::Info', lazy, builder => '_get_info',
								handles =>	{
												seconds => 'secs',
											},
						);
	has status		=>	( rw, isa => Str, lazy, builder => '_guess_status', );


	# CTORS & BUILDERS

	around BUILDARGS ($class: %args)
	{
		if (exists $args{'file'})
		{
			if ( not ( blessed $args{'file'} and $args{'file'}->isa('Path::Class::File') ) )
			{
				$args{'file'} = file($args{'file'});
			}
		}
		elsif (exists $args{'dir'})
		{
			if ( not ( blessed $args{'dir'} and $args{'dir'}->isa('Path::Class::Dir') ) )
			{
				$args{'dir'} = dir($args{'dir'});
			}
		}
		else
		{
			die("must supply either `file' or `dir' to create $CLASS");
		}

		$class->$orig(%args);
	}


	method _get_sample_file
	{
		return file( first { /\.mp3$/ } grep { ! -d } $self->dir->children );
	}


	method _get_tag
	{
		my $file = $self->file;
		my $tag = MP3::Tag->new("$file");
		croak("couldn't get tag for $file [$!]") unless $tag;

		$tag->get_tags;
		return $tag;
	}


	method _get_info
	{
		croak("can't retrieve time for an album") if $self->is_album;
		my $file = $self->file;
		my $info = MP3::Info->new("$file");
		croak("couldn't get info for $file [$!]") unless $info;
		return $info;
	}


	method _guess_status
	{
		my $status;
		if (not $self->has_v2)
		{
			$status = 'untagged';
		}
		elsif ($self->get_frame('TXXX[MusicBrainz Artist Id]'))
		{
			$status = $self->get_frame('TMED') // $self->get_frame('TORY') // $self->get_frame('TXXX[SCRIPT]')
					? 'DIRTY'
					: 'clean';
		}
		else
		{
			$status = 'manual';
		}

		return $status;
	}


	# HELPER METHODS

	method _is_binary ($data)
	{
		return undef unless defined $data;
		# see http://www.justskins.com/forums/is-data-binary-or-47078.html
		local $_ = $data;
		length > 5 && (tr/ -~//c / length) >= .3;
	}

	method _dirs_are_equal ($dir1, $dir2)
	{
		return $dir1->absolute->resolve eq $dir2->absolute->resolve;
	}


	# PSEUDO-ATTRIBUTES

	method has_v1		{ exists $self->_tag->{ID3v1} }
	method has_v2		{ exists $self->_tag->{ID3v2} }

	method v1_data		{ $self->_tag->{ID3v1}->all }


	method has_pic		{ $self->_tag->have_id3v2_frame_by_descr('APIC') }


	method album_path	{ $self->_dirs_are_equal( $self->file->dir, $SINGLES_DIR ) ? undef : $self->file->dir }
	method album_dir	{ $self->album_path ? $self->album_path->basename : undef }

	method filename
	{
		# have to qualify the method from Music so that it isn't confused with this one
		return Music::filename($self->_tag->interpolate('%a - %t%E'));
	}


	method has_sortkey	{ defined $self->get_frame('TSO2') }
	method sortkey		{ $self->get_frame('TSO2') // uc $self->album_dir }


	method time			{ sprintf("%d:%02d", int($self->seconds / 60), $self->seconds % 60) }


	# ACTION METHODS

	method save
	{
		$self->config( write_v24 => 1 );
		delete $self->_tag->{'ImageExifTool'};		# cheap hack to avoid unsightly (and pointless) warning
		$self->_tag->update_tags;
	}


	method print_frames ($prefix = '')
	{
		printf "$prefix%-40s => %s\n", $self->get_frame_for_display($_) foreach $self->frames;
	}


	method frames
	{
		return $self->_tag->id3v2_frame_descriptors;
	}


	method get_frame ($frame)
	{
		return $self->_tag->select_id3v2_frame_by_descr($frame);
	}

	method get_frame_for_display ($frame, $width = 70)
	{
		my $value = $self->get_frame($frame);
		if ( not defined $value )
		{
			$value = '<<NULL>>';
		}
		elsif (ref $value eq 'HASH')
		{
			my $keys = join(',', sort keys %$value);
			if ($keys eq 'Text,_Data')
			{
				$frame = "${frame} {$value->{Text}}";
				$value = $value->{_Data};
			}
			elsif ($keys =~ /Description,.*_Data/)
			{
				$frame = "${frame} {$value->{Description}}+";
				$value = $value->{_Data};
			}
			else
			{
				$value = "{$keys}";
			}
		}
		if ( $self->_is_binary($value) )
		{
			$value = '<<BINARY>>';
		}
		elsif ( length($value) > $width)
		{
			$value = substr($value, 0, $width - 1) . '…';
		}
		return ($frame, $value);
	}


	method set_frame ($frame, $newval)
	{
		$self->_tag->select_id3v2_frame_by_descr($frame, $newval);
		return $self;													# for chaining
	}


	method rm_frame ($frame)
	{
		$self->set_frame($frame, undef);
		return $self;													# for chaining
	}

}


1;
