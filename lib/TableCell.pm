package TableCell;

use strict;

#
#     $cell         = TableCell->new;
#     $cell         = TableCell->new( $tag );
#     $cell         = TableCell->new( $tag, $text );
#     $cell         = TableCell->new( $tag, $text, $escaped );
#
#     $cell         = TableCell->TD( $text );
#     $cell         = TableCell->TD( $text, $escaped );
#
#     $cell         = TableCell->TH( $text );
#     $cell         = TableCell->TH( $text, $escaped );
#
#     $blank_cell   = TableCell->nbsp;
#
#     $tag          = $cell->tag()
#     $cell         = $cell->set_tag( $tag )
#
#     $text         = $cell->text()
#     $cell         = $cell->set_text( $text );
#     $cell         = $cell->set_text( $text, $escaped );
#     $cell         = $cell->escape_text()
#
#     $attr_value   = $cell->attribute( $key )
#     $cell         = $cell->set_attribute( $key => $value, ... )
#     $cell         = $cell->del_attribute( $key, ... )
#
#     %attributes   = $cell->attributes()
#    \%attributes   = $cell->attributes()
#
#     %style        = $cell->style()
#    \%style        = $cell->style()
#     $cell         = $cell->add_style( $key => $value, ... )
#     $cell         = $cell->del_style( $key )
#
#     $cell_as_html = $cell->as_html()
#     [$text,$tag]  = $cell->as_text_tag()
#     $enhanced     = $cell->as_enhanced()
#

sub new {
    my ( $self, $tag, $text, $escaped ) = @_;
    bless { _tag => $tag ? uc $tag : 'TD',
            defined $text    ? ( _text    => $text    ) : (),
            defined $escaped ? ( _escaped => $escaped ) : ()
          };
}


sub TD {
    my ( $self, $text, $escaped ) = @_;
    bless { _tag => 'TD',
            defined $text    ? ( _text    => $text    ) : (),
            defined $escaped ? ( _escaped => $escaped ) : ()
          };
}


sub TH {
    my ( $self, $text, $escaped ) = @_;
    bless { _tag => 'TH',
            defined $text    ? ( _text    => $text    ) : (),
            defined $escaped ? ( _escaped => $escaped ) : ()
          };
}


sub nbsp { bless { _tag => 'TD', _text => '&nbsp;', _escaped => 1 } }


sub tag { my $self = shift; $self->{ _tag } }


sub set_tag {
    my ( $self, $tag ) = @_;
    return undef unless $self;

    $self->{ _tag } = $tag;
    $self;
}


sub text {
    my $self = shift;
    return undef unless $self;

    $self->{ _text };
}


sub set_text {
    my ( $self, $text, $escaped ) = @_;
    return undef unless $self;

    $self->{ _escaped } = $escaped if defined $escaped;
    $self->{ _text } = $text;
    $self;
}


sub attribute {
    my ( $self, $key ) = @_;
    return undef unless $self && $key;

    $key = uc $1 . lc $2  if $key =~ /^(.)(.*)$/;
    $self->{ $key };
}


sub attributes {
    my $self = shift;
    return wantarray ? () : [] unless $self;

    my %attr = map { $_ => $self->{ $_ } } grep { /^[A-Z]/ } keys %$self;
    wantarray ? %attr : \%attr;
}


sub set_attribute {
    my $self = shift;
    return 0 unless $self && @_;

    local $_;
    while ( defined( $_ = shift ) ) {
        $_ = uc $1 . lc $2  if /^(.)(.*)$/;
        my $val = lc( shift || '' );
        if ( $_ eq 'Align' ) {
            add_style( $self, 'align' => $val );
        }
        elsif ( $_ eq 'Valign' ) {
            $val = 'middle' if $val eq 'center';
            add_style( $self, 'vertical-align' => $val );
        }
        elsif ( $_ eq 'Bgcolor' ) {
            add_style( $self, 'background-color' => $val );
        }
        elsif ( $_ eq 'Nowrap' ) {
            add_style( $self, 'white-space' => 'nowrap' );
        }
        elsif ( $_ eq 'Style' ) {
            my $styles = &split_styles( $val );
            add_style( $self, %$styles ) if keys %$styles;
        }
        else {
            $self->{ $_ } = $val;
        }
    }
    $self;
}


sub del_attribute {
    my $self = shift;
    return 0 unless $self;

    local $_;
    while ( defined( $_ = shift ) ) {
        $_ = uc $1 . lc $2  if /^(.)(.*)$/;
        if ( $_ eq 'Align' ) {
            del_style( $self, 'align' );
        }
        elsif ( $_ eq 'Valign' ) {
            del_style( $self, 'vertical-align' );
        }
        elsif ( $_ eq 'Bgcolor' ) {
            delete_style( $self, 'background-color' );
        }
        elsif ( $_ eq 'Nowrap' ) {
            del_style( $self, 'white-space' );
        }
        elsif ( exists $self->{ $_ } ) {
            delete $self->{ $_ };
        }
    }
    $self;
}


sub style {
    my $self = shift;
    return wantarray ? () : [] unless $self && $self->{ _style };

    my %style = $self->{ _style };
    wantarray ? %style : \%style;
}


sub add_style {
    my $self = shift;
    return 0 unless $self && @_;

    local $_;
    my $styles = $self->{ _style } ||= {};
    while ( defined( $_ = shift ) ) {
        my $val = shift;
        if ( defined $val && $val =~ /\S/ ) {
            $val =~ s/^\s+//;
            $val =~ s/[;\s]+$//;
            $styles->{ lc $_ } = $val;
        }
    }
    $self;
}


sub del_style {
    my $self = shift;
    return 0 unless $self;

    local $_;
    my $styles = $self->{ _style } ||= {};
    while ( defined( $_ = shift ) ) {
        next unless exists $styles->{ lc $_ };
        $styles->{ lc $_ } = shift;
    }
    $self;
}


sub escape_text {
    my $self = shift;
    return undef unless $self && exists $self->{ _text };

    if ( ! $self->{ _escaped } ) {
        $self->{ _escaped } = 1;
        $self->{ _text } = &html_esc( $self->{ _text } );
    }
    $self;
}


#     $html_cell = as_html()
#     $text_tag  = as_text_tag()
#     $enhanced  = as_enhanced()


sub as_html {
    my $self = shift;
    return undef unless $self && $self->{ _tag };

    my $bare_tag = &bare_tag( $self );
    my $end_tag  = "</$self->{_tag}>";

    join( '', '<', $bare_tag, '>',
              $self->{_escaped} ? $self->{_text} : &html_esc( $self->{_text} ), 
              $end_tag
        );
}


sub as_text_tag {
    my $self = shift;
    return undef unless $self && $self->{ _tag };

    my $bare_tag = &bare_tag( $self );
    my $end_tag  = "</$self->{_tag}>";

    [ $self->{_escaped} ? $self->{_text} : &html_esc( $self->{_text} ),
      $bare_tag
    ];
}


sub as_enhanced {
    my $self = shift;
    return undef unless $self && $self->{ _tag };

    my $styles = &styles_value( $self );
    join( '', $styles ? "|^$styles^|" : '',
              $self->{_escaped} ? $self->{_text} : &html_esc( $self->{_text} )
        );
}


sub cell_tag { $_[0] ? join( '', '<', &bare_tag( @_ ), '>') : undef }


sub bare_tag {
    my $self = shift;
    return undef unless $self && $self->{ _tag };

    my $style = &styles_value( $self );
    $self->{ Style } = $style if $style;

    my $tag = $self->{_tag};
    my @attr = ();
    foreach ( sort grep { /^[A-Z]/ } keys %$self ) {
        my $val = $self->{ $_ };
        if ( ! defined( $val ) ) {
            push @attr, $_;
        }
        elsif ( $val =~ /^[.#%0-9A-Za-z]+$/ ) {
            push @attr, "$_=$val";
        }
        else {
            $val =~ s/"/\\"/g;
            push @attr, qq($_="$val");
        }
    }

    join( ' ', $tag, @attr );
}


sub split_styles {
    my $value = shift;
    my %styles = ();
    if ( $value ) {
        # Strip quotes and leading and trailing space, just in case
        $value =~ s/\\"/"/g if $value =~ s/^\s*"(.*)"\s*$/$1/;
        $value =~ s/\\'/'/g if $value =~ s/^\s*'(.*)'\s*$/$1/;
        $value =~ s/^\s+//;
        $value =~ s/\s+$//;
        # Split into attributes and values
        my %styles = map { /^([^s:]+)\s*:\s*([^\s:][^:]*)$/ ? ( $1, $2 ) : () } 
                     split /\s*;\s*/, $value;
    }

    wantarray ? %styles : \%styles;
}


sub styles_attribute {
    my $value = &styles_value( @_ );
    $value ? qq(Style="$value") : '';
}


sub styles_value {
    my $self = shift;
    my $styles;
    return '' unless $self && ( $styles = $self->{ _style } ) && keys %$styles;

    join( ' ', map { "$_: $styles->{$_};" } sort keys %$styles );
}


#
#  Escape HTML body text:
#
sub html_esc { $_ = $_[0]; s/\&/&amp;/g; s/\>/&gt;/g; s/\</&lt;/g; $_ }


#
#  Escape a URL:
#
my %url_esc = (  ( ' ' => '%20',
                   '"' => '%22',
                   '#' => '%23',
                   '$' => '%24',
                   ',' => '%2C' ),
               qw(  !      %21
                    %      %25
                    +      %2B
                    &      %2D
                    /      %2F
                    :      %3A
                    ;      %3B
                    <      %3C
                    =      %3D
                    >      %3E
                    ?      %3F
                    @      %40
                    [      %5B
                    \      %5C
                    ]      %5D
                    `      %60
                    {      %7B
                    |      %7C
                    }      %7D
                    ~      %7E
                 )
              );

sub url_encode { join( '', map { $url_esc{$_}||$_ } split //, $_[0] ) }



1;
