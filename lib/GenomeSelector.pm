package GenomeSelector;

#
#  Build a genome selection system. There are four essential routines, each
#  of which returns an essential piece of HTML.
#
#  Before first form (can be in <HEAD>)
#
#      $html .= genomeHTML( $fig, $listname )
#      $html .= scriptHTML()
#
#  In the body of the HTML <FORM>:
#
#      $html .= selectHTML( $formname, $listname, $paramname, \%options )
#

use strict;
use Data::Dumper;

sub genomeHTML
{
    my ( $fig, $listname ) = @_;
    my ( $g, $n, $t ) = ( 0, 0, 0 );  # sort order indices for gid, name and taxonomy
    my @gid = map  { $_->[6]   = ++$n;
                     $_->[0]   = qq("$_->[0]");
                     $_->[1]   =~ s/\\/\\\\/g;
                     $_->[1]   =~ s/"/""/g;
                     $_->[1]   = qq("$_->[1]");
                     $_->[2]   = qq("@{[uc substr($_->[2],0,1)]}");  # A B E M P V
                     $_;
                   }
              sort { lc $a->[1] cmp lc $b->[1] }
              map  { $_->[7] = ++$t; $_ }
              sort { lc $a->[7] cmp lc $b->[7] || lc $a->[1] cmp lc $b->[1] }
              map  { $_->[8] = ++$g; $_ }
              sort { $a->[8]->[0] <=> $b->[8]->[0] || $a->[8]->[1] <=> $b->[8]->[1] }
              map  { $_->[5] = ( $_->[1] =~ m/\bplasmid\b/i || $_->[7] =~ m/\bplasmid[s]\b/i ) ? 1 : 0;
                     $_->[2] = $_->[7] = "Plasmid"       if $_->[5];
                     $_->[2] = $_->[7] = "Z metagenome"  if $_->[2] =~ m/^Environ/i;
                     $_->[2] = $_->[7] = "Z unclasified" if $_->[2] =~ m/^Un/i;
                     $_;
                   }
              map  {
                     [ $_->[0],                               # 0  gid
                       $_->[1],                               # 1  name
                       $_->[3],                               # 2  domain
                       $fig->number_of_contigs($_->[0]) + 0,  # 3  contigs
                       $_->[6] ? 1 : 0,                       # 4  complete
                       undef,                                 # 5  plasmid
                       undef,                                 # 6  name sort index
                       $_->[7],                               # 7  taxonomy sort index
                       [ split /\./, $_->[0] ]                # 8  gid sort index
                     ]
                   }
              # genome, gname, szdna, maindomain, pegs, rnas, complete, taxonomy
              #    0      1      2        3         4     5      6          7
              @{ $fig->genome_info() };

    <<"GenomeListPrefix";

<!-- ------------------------------------------------- -->
<!--  Data for genome selector                         -->
<!--  Must come before the selector code that uses it  -->
<!-- ------------------------------------------------- -->
<SCRIPT Language="JavaScript">
//
// Genomes are defined by:
//
//    0    1      2        3        4         5           6               7                8
// [ gid, name, domain, contigs, complete, plasmid, name_sort_order, tax_sort_order, gid_sort_order ]
//
document.$listname =
  [
@{[join( ",\n", map { "    [ " . join( ", ", @$_ ) . " ]" } @gid )]}
  ];
</SCRIPT>

GenomeListPrefix
}


sub scriptHTML
{
    qq(<SCRIPT Src="Html/css/GenomeSelector.js" Type="text/javascript"></SCRIPT>\n)
}


sub scriptHTML2
{
    <<"Selector_Script";

<!-- ---------------------------------- -->
<!-- Action scripts for genome selector -->
<!-- ---------------------------------- -->

<SCRIPT Language="JavaScript">

function update_genomes( form, param )
{
    var genlistname = param + '_current';
    form[genlistname] = sort_genomes( form, genome_set( form, param ) );
    filter_and_show_genomes( form, param );
}


//
//  Each genome is defined by an Array object:
//
//     0    1      2        3        4         5           6               7                8
//  [ gid, name, domain, contigs, complete, plasmid, name_sort_order, tax_sort_order, gid_sort_order ]
//
//  The script adds Option objects for <SELECT> list elements (9 is name first, 10 is gid first)
//
function genome_set( form, param )
{
    var archaea  = form.ShowArchaea.checked;
    var bacteria = form.ShowBacteria.checked;
    var eucarya  = form.ShowEucarya.checked;
    var viruses  = form.ShowViruses.checked;
    var plasmids = form.ShowPlasmid.checked;
    var unclass  = form.ShowUnclass.checked;
    if ( ! ( archaea || bacteria || eucarya || viruses || plasmids || unclass ) )
    {
        archaea  = true;
        bacteria = true;
        eucarya  = true;
    }
    var partial  = form.ShowPartial.checked;

    var genlistname = param + '_genomes';
    var allgens     = form[genlistname];
    var mygens      = new Array();
    for ( var i = 0; i < allgens.length; i++ )
    {
        var g = allgens[i];
        // Deal with genomes that are not screened for completeness
        var is_plasmid = g[5] || ( g[2] == "P" );
        if ( is_plasmid  ) { if ( plasmids ) { mygens.push( g ) } continue }
        if ( g[2] == "V" ) { if ( viruses )  { mygens.push( g ) } continue }
        if ( g[2] == "Z" ) { if ( unclass )  { mygens.push( g ) } continue }
        if ( g[4] || partial )
        {
            switch ( g[2] )
            {
                case "A": if ( archaea  ) { mygens.push( g ) } break
                case "B": if ( bacteria ) { mygens.push( g ) } break
                case "E": if ( eucarya  ) { mygens.push( g ) } break
                default:  if ( unclass  ) { mygens.push( g ) } 
            }
        }
    }
    return mygens;
}


function filter_and_show_genomes( form, param )
{
    var genlist;
    var curlistname = param + '_current';
    var genlistname = param + '_genomes';
    if ( form.TextFilter.value.length )
    {
        var gens = form[curlistname];
        var filter = new RegExp( form.TextFilter.value, "i" );
        genlist = new Array();
        for ( var i = 0; i < gens.length; i++ )
        {
            if ( filter.test( gens[i][1] ) ) { genlist.push( gens[i] ) }
        }
    }
    else
    {
        genlist = form[curlistname];
    }

    var optlist = form[param].options;
    var order   = radio_value( form.SortBy );
    
    optlist.length = 0;
    for ( var i = 0; i < genlist.length; i++ )
    {
        optlist[i] = genome_option( genlist[i], order );
    }
    var counttext = document.getElementById(form.name + "_" + param + "_GenCount");
    counttext.innerHTML = optlist.length + " of " + form[genlistname].length + " genomes";
}


function sort_genomes( form, genomes )
{
    switch ( radio_value( form.SortBy ) )
    {
        case "name":  genomes.sort( by_name     ); break
        case "taxon": genomes.sort( by_taxonomy ); break
        case "gid":   genomes.sort( by_gid      ); break
    }
    return genomes;
}

function by_name(a,b)     { return a[6] - b[6] }
function by_taxonomy(a,b) { return a[7] - b[7] }
function by_gid(a,b)      { return a[8] - b[8] }


//
//  Build an Option object and cache it in the genome Array.
//  There are two separate forms: name first (g[9]) and gid first (g[10]).
//
function genome_option( g, order )
{
    if ( ! order ) { order = "name" }
    var text = ( order == "gid" ) ? g[0] + String.fromCharCode(32,0x2014,32) + g[1] + " [" + g[3] + " contigs]"
                                  : g[1] + " (" + g[0] + ") [" + g[3] + " contigs]";
    return new Option( text, g[0] );
}


//
//  Find the value of the selected radio button
//
function radio_value( radio )
{
    for ( var i = 0; i < radio.length; i++ )
    {
        if ( ! radio[i].checked ) { continue }
        return radio[i].value;
    }
    return null;
}


//
//  Escape text that will be used as HTML -- currently not used
//
var entityMap = { "&": "&amp;", "<": "&lt;", ">": "&gt;" };

function escape_html( string )
{
    return String(string).replace( /[&<>]/g, function(s) { return entityMap[s] } );
}

</SCRIPT>

Selector_Script
}


sub selectHTML
{
    my ( $formname, $listname, $paramname, $opts ) = @_;
    $opts ||= {};

    my $FilterTextSize = $opts->{ FilterTextSize } || 72;
    my $GenomeListSize = $opts->{ GenomeListSize } || 10;
    my $Multiple       = $opts->{ Multiple       } ? ' Multiple' : '';

    #                 Parameter,       Name
    my @filters = ( [ ShowArchaea  => 'Archaea' ],
                    [ ShowBacteria => 'Bacteria' ],
                    [ ShowEucarya  => 'Eucarya' ],
                    [ ShowViruses  => 'Viruses' ],
                    [ ShowPlasmid  => 'Plasmids' ],
                    [ ShowUnclass  => 'Unclassified' ]
                  );

    my %show;
    foreach ( map { $_->[0] } @filters ) { $show{ $_ } = 1 if $opts->{ $_ } }
    if ( ! keys %show )
    {
        $show{ ShowArchaea } = $show{ ShowBacteria } = $show{ ShowEucarya } = 1;
    }

    push @filters, [ ShowPartial => 'Partial genomes' ];
    $show{ ShowPartial } = 1 if $opts->{ ShowPartial };

    my @showboxes = map { qq(    <INPUT Type="checkbox" Name="$_->[0]" Value=1 )
                        . ( $show{$_->[0]} ? 'Checked ' : '' )
                        . qq(onClick="update_genomes( this.form, '$paramname' ); return true;" /> $_->[1]<BR />\n)
                        }
                    @filters;

    my @sorts = ( [ name  => 'Name' ],
                  [ taxon => 'Taxonomy' ],
                  [ gid   => 'Genome ID' ]
                );
    my %sort;
    my $sortby = $opts->{ SortBy } || '';
    foreach ( map { $_->[0] } @sorts ) { $sort{ $_ } = 1 if $sortby eq $_ }
    $sort{ name } = 1 if ! keys %sort;

    my @sortbuttons = map { qq(      <INPUT Type="radio" Name="SortBy" Value="$_->[0]" )
                          . ( $sort{ $_->[0] } ? 'Checked ' : '' )
                          . qq(onClick="update_genomes( this.form, '$paramname' ); return true;" /> $_->[1]<BR />\n)

                          }
                      @sorts;

    # Doing this in-line is a pain, so define it first

    my $selectgenlist = $formname . qq(['${paramname}_genomes']);

    <<"GenomeSelectorBody";

<!-- Associate the genome list with the <FORM>, simplifying the action scripts -->

<SCRIPT Language="JavaScript">
document.$selectgenlist = document.$listname;
</SCRIPT>

<!-- Organize the genome selector in a <TABLE> -->

<TABLE>
  <TR>
    <TD ColSpan=3>
      Genome text filter:
      <INPUT Type="text" Name="TextFilter" Size=$FilterTextSize
             OnChange="filter_and_show_genomes( this.form, '$paramname' ); return false;"
             OnKeyDown="if (event.keyCode != 13) return true; filter_and_show_genomes( this.form, '$paramname' ); return false;" />
    </TD>
  </TR>

  <TR>
    <TD>
      <!-- The selection list: options are filled in by JavaScript -->
      <SELECT Name="$paramname" Size=$GenomeListSize $Multiple>
      </SELECT><BR />
      <DIV Id="${formname}_${paramname}_GenCount"></DIV>
    </TD>

    <TD WIDTH=6></TD>

    <TD STYLE="vertical-align:top;">
      Displayed genomes:<BR />
@showboxes
    </TD>

    <TD WIDTH=6></TD>

    <TD STYLE="vertical-align:top;">
      Sorted by:<BR />
@sortbuttons
      <BR />
    </TD>
  </TR>
</TABLE>

<!-- Fill in the genome selection list -->
<SCRIPT Language='JavaScript'>
update_genomes( document.$formname, '$paramname' );
</SCRIPT>
GenomeSelectorBody
}


1;
