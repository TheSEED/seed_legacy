#
# Copyright (c) 2003-2013 University of Chicago and Fellowship
# for Interpretations of Genomes. All Rights Reserved.
#
# This file is part of the SEED Toolkit.
#
# The SEED Toolkit is free software. You can redistribute
# it and/or modify it under the terms of the SEED Toolkit
# Public License.
#
# You should have received a copy of the SEED Toolkit Public License
# along with this program; if not write to the University of Chicago
# at info@ci.uchicago.edu or the Fellowship for Interpretation of
# Genomes at veronika@thefig.info or download a copy from
# http://www.theseed.org/LICENSE.TXT.
#

### start

#  Script parameters:
#
#  Actions:
#
#  update                  Request to update the display with the current
#                             paramter values.  This is the default action
#                             if no other value is specified.
#  blastp                  Request to blastp currently defined peg against
#                             the complete genomes
#  create                  Request to create the currently defined peg
#                             (requires user, start and function.  The end
#                             location is implicit in the genetic code and
#                             ignore values)
#
#  Required parameters:
#
#  user=name               User (required)
#  genome=genome_id        Genome for the feature (required)
#
#  Either location or covering is required:
#
#  location=locaton        Should be a precise location of proposed orf
#                             but currently is synonym for "covering"
#  covering=location       The location specified will define the frame
#                             and provide a focus region from defining the
#                             new peg
#
#  Options for display and actions:
#
#  npre=number             Is the number of nucleotides prefixed to the
#                             "covering" location (multiple of 3, D=270)
#  npost=number            Is the number of nucleotides appended to the
#                             "covering" location (multiple of 3, D=270)
#  old_pre=number          Hidden parameter giving previous value of npre.
#                             this is essential for coordinate tracking
#  start=triplet_number    Triplet number of selected start codon in old
#                             numbering
#  ignore=triplet_number   Triplet number(s) of stop codon(s) that are to
#                             be ignored (in old numbering)
#  is_start=NNN            Defines an allowed start codon.  If any are
#                             specified, they must all be defined.
#  code_opts=NNN.A         Redefines the amino acid assigned to a codon
#                             in format codon dot amino acid
#  function=function       Function to be assigned (as previously proposed)
#  assign_from=fid         Assign function from fid associated with radio
#                             button on previous page (will replace previous
#                             fucntion)
#  newfunction=function    Function assigned from textbox (replaces previous
#                             value)
#  blast_pad=number        Number of extra triplets to add to each end of
#                             currently defined peg in formulating blast
#                             query (D=20).  This allows discovery of
#                             additional similarity.
#  change_start=option     Required to create a peg with same end point as a
#                             current one, and defines the disposition of the
#                             overlapping one.  Option values are "keep_both"
#                             and "replace".  (The start sites of the new and
#                             existing features must differ, duplicates of a
#                             feature are not allowed.)

use FIG;
use FIG_CGI;
use Sim;
use SimsTable;

use strict;
use Tracer;
use gjoseqlib      qw( %genetic_code );
use gjoparseblast  qw( blast_hsp_list next_blast_hsp );
use BlastInterface qw( verify_db );

use URI::Escape;  # uri_escape
use POSIX;
use HTML;
use Time::HiRes    qw( sleep );

main_routine();

#==============================================================================
#  Main routine to localize variables:
#==============================================================================

sub main_routine
{
    my( $fig, $cgi, $user );
    my $this_script = "propose_new_peg.cgi";

    eval { ( $fig, $cgi, $user ) = FIG_CGI::init( debug_save   => 0,
                                                  debug_load   => 0,
                                                  print_params => 0
                                                );
    };

    if ( $@ ne "" )
    {
        my $err = $@;
        my( @html );
        push @html, $cgi->p("Error connecting to SEED database.");
        if ( $err =~ /Could not connect to DBI:.*could not connect to server/ )
        {
            push @html, $cgi->p( "Could not connect to relational database of type "
                               . "$FIG_Config::dbms named $FIG_Config::db on port "
                               . "$FIG_Config::dbport."
                               );
        }
        else
        {
            push @html, $cgi->pre( $err );
        }
        &HTML::show_page( $cgi, \@html, 1 );
        return;
    }

    Trace("Connected to FIG.") if T(2);

    if (0) {
        my $VAR1;
        eval( join( "", `cat /tmp/new_peg_parms` ) );
        $cgi = $VAR1;
        # print STDERR &Dumper($cgi);
    }

    if (0) {
        print $cgi->header;
        print "<pre>\n";
        foreach ( $cgi->param )
        {
		    print "$_\t:", join( ",", $cgi->param($_) ), ":\n";
        }
        print "</pre>\n";

        if (0 and open( TMP, ">/tmp/new_peg_parms") )
        {
            print TMP &Dumper( $cgi );
            close( TMP );
        }
        return;
    }

    $ENV{"PATH"} = "$FIG_Config::bin:$FIG_Config::ext_bin:" . $ENV{"PATH"};

    my $html = [];
    push @$html, $cgi->title( 'The SEED: Propose New Protein Encoding Gene' );

    #  genome=Genome
    #  location=Contig_From_To

    my $genome   = $cgi->param( 'genome' );
    my $organism = $fig->genus_species( $genome );
    my $location = $cgi->param( 'location' );
    my $covering = $cgi->param( 'covering' );

    if ( $genome && $organism && ( $location || $covering ) )
    {
        propose_in_frame( $fig, $cgi, $user, $html, $genome,
                          $location, $covering, $organism
                        );
    }

    else
    {
        push @$html, $cgi->h2( 'Script requires a genome and a location' );
    }

    &HTML::show_page( $cgi, $html, 1 );
}
# End of main_routine()

#==============================================================================
#  Propose a peg that covers a region in a given frame:
#==============================================================================

sub propose_in_frame
{
    my ( $fig, $cgi, $user, $html, $genome, $location, $covering, $organism ) = @_;

    Trace("Propose a peg in a given frame") if T(2);

    my $extra = 270;

    #---------------------------------------------------------------------------
    #  Interpret the location information:
    #---------------------------------------------------------------------------

    my ( $contig, $n1, $n2, $dir, $len, $clen );
    my $ttl = 0;
    my @loc;
    my $loc = $location || $covering;
    foreach ( split /,/, $loc )
    {
        my ( $contig, $n1, $n2 ) = $_ =~ /^(.*)_(\d+)_(\d+)$/;
        if ( $contig && $n1 && $n2
          && ( $clen = $fig->contig_ln( $genome, $contig ) )
           )
        {
            $dir = ( $n2 >= $n1 ) ? +1 : -1;
            $len = ( $n2>$n1 ? $n2-$n1 : $n1-$n2 ) + 1;
            $ttl += $len;
            push @loc, [ $contig, $n1, $n2, $dir, $len, $clen ];
        }
        else
        {
            push @$html, $cgi->h2( "Bad location in genome $genome: $loc\n" );
            return;
        }
    }

    if ( ( $ttl % 3 ) != 0 )
    {
        push @$html, $cgi->h2( "Location in genome $genome is not an even "
                             . "number of codons: $loc\n"
                             );
        return;
    }

    #---------------------------------------------------------------------------
    #  Build a description of the DNA context to be displayed.  The elements of
    #  the description are in the form:
    #
    #     [ $contig, $n1, $n2, $dir, $len, $clen ]
    #---------------------------------------------------------------------------

    my @loc2 = @loc;                    # Location of DNA to show

    #---------------------------------------------------------------------------
    #  Determine upstream sequence
    #---------------------------------------------------------------------------
    #  This might run off end of contig.  We really want to remember if we did
    #  so, and provide user feedback, and the chance to initiate at the first
    #  triplet displayed (this last point is handled through p1_contig_end).

    my $npre  = $cgi->param('npre');    # Must be defined for start and ignore
                                        # locations to be mapped
    $npre = $extra if ! defined( $npre );

    ( $contig, $n1, $n2, $dir, $len, $clen ) = @{ $loc2[0]} ;
    my ( $p1, $p1_contig_end );
    if ( $dir > 0 )
    {
        $npre  = $n1 - 1 if $npre >= $n1;  # Truncate to fit
        $npre -= $npre % 3;                # Make it a multiple of 3
        $p1    = $n1 - $npre;              # Start of displayed DNA
        $p1_contig_end = 1 if $p1 <= 3;    # Reach contig end?
    }
    else
    {
        $npre  = $clen - $n1  if $n1 + $npre > $clen;  # Truncate to fit
        $npre -= $npre % 3;                # Make it a multiple of 3
        $p1    = $n1 + $npre;              # Start of displayed DNA
        $p1_contig_end = 1 if $p1+3 > $clen;  # Reach contig end?
    }
    $loc2[0]->[1]  = $p1;
    $loc2[0]->[4] += $npre;

    #---------------------------------------------------------------------------
    #  Determine downstream sequence
    #---------------------------------------------------------------------------

    my $npost = $cgi->param('npost');
    $npost = $extra if ! defined( $npost );

    ( $contig, $n1, $n2, $dir, $len, $clen ) = @{$loc2[-1]};
    my $p2;
    if ( $dir > 0 )
    {
        $npost  = $clen - $n2  if $n2 + $npost > $clen;  # Truncate to fit
        $npost -= $npost % 3;           # Make it a multiple of 3
        $p2     = $n2 + $npost;
    }
    else  # July 24, 06, fix truncation location error -- GJO
    {
        $npost  = $n2 - 1 if $npost >= $n2;  # Truncate to fit
        $npost -= $npost % 3;           # Make it a multiple of 3
        $p2     = $n2 - $npost;
    }
    $loc2[-1]->[2]  = $p2;
    $loc2[-1]->[4] += $npost;

    #---------------------------------------------------------------------------
    #  We have a window to look at, let's put things in it
    #---------------------------------------------------------------------------
    #  The following two parameters are based on triplet numbering relative to
    #  the DNA region displayed.  Because the user can reset the amount of DNA
    #  prefixed, the numbers might shift.  We will require that the previous
    #  prefix length be defined for them to be used:
    #
    #  We need the number of displayed triplets to know if an old locations
    #  falls outside of the new window

    my $c1 =       $npre / 3;  # Prefixed triplets
    my $c2 = $c1 + $ttl  / 3;  # Triplets in prefix and requested region
    my $c3 = $c2 + $npost/ 3;  # Total triplets displayed

    my $start  = undef;
    my %ignore = ();

    my $old_pre = $cgi->param('old_pre');
    if ( defined( $old_pre ) )
    {
        my $offset  = ( $npre - $old_pre ) / 3;

        #  What is the currently selected start (zero = undefined)?

        if ( $cgi->param('start') )
        {
            $start = $cgi->param('start') + $offset;
            $start = undef if ( $start <= 0 ) || ( $start > $c3 );
        }

        #  Which stop codons are marked to be ignored?

        my $new;
        %ignore = map { $new = $_ + $offset;
                        ( $new > 0 && $new <= $c3 )? ( $new => 1 ) : ()
                      }
                  $cgi->param('ignore');
    }
    $cgi->delete('old_pre');  # Annoying feature in cgi: old values are
                              # sticky unless explicitly deleted.

    #---------------------------------------------------------------------------
    #  What is the current set of allowed start codons?
    #---------------------------------------------------------------------------

    my @is_start = $cgi->param('is_start');
    ( @is_start > 0 ) or ( @is_start = qw( ATG GTG TTG ) );
    my %is_start = map { $_ => 1 } @is_start;

    #---------------------------------------------------------------------------
    #  What genetic code do we use?
    #---------------------------------------------------------------------------

    my %gencode = map { $_ => $gjoseqlib::genetic_code{ $_ } }
                  keys %gjoseqlib::genetic_code;

    foreach ( $cgi->param('code_opts') )
    {
        my ( $codon, $aa ) = split /\./;
        $gencode{ $codon } = $aa;
    }

    #---------------------------------------------------------------------------
    #  Is there a proposed function
    #---------------------------------------------------------------------------

    my $function = $cgi->param('function') || '';

    #  Let assign_from override the function

    my $assign_from = $cgi->param('assign_from') || '';
    if ( $assign_from )
    {
        my $tmp_func = $fig->function_of( $assign_from, $user );
        $function = $tmp_func if $tmp_func;
    }

    #  And of course the text box overrides the function.  We might want to
    #  change the order of these two operations.  Which takes precidence, the
    #  text box or the radio button?  Currently the text box has the last say.

    my $newfunction = $cgi->param('newfunction');
    $newfunction =~ s/^\s+//;
    $newfunction =~ s/\s+$//;
    $newfunction =~ s/\s+/ /g;
    $function = $newfunction if $newfunction;
    $cgi->delete('newfunction');  #  Sigh.  The box contents are sticky

    #---------------------------------------------------------------------------
    #  Does the user think that he/she/it is ready to create a feature?
    #---------------------------------------------------------------------------

    my $create = $cgi->param('create') || undef;

    #---------------------------------------------------------------------------
    #  Is BLASTP being requested?
    #---------------------------------------------------------------------------

    my $blastp = $cgi->param('blastp') || undef;

    #  Extra triplets around selected orf in a BLASTP search

    my $blast_pad = $cgi->param('blast_pad');
    defined( $blast_pad ) or $blast_pad = 20;

    #---------------------------------------------------------------------------
    #  Most or all of the incoming state information has been examined
    #  It is time to put together the page.
    #---------------------------------------------------------------------------
    #  Put the displayed information in a FORM.  For unclear reasons I have been
    #  getting killed by state information in $cgi.  I have finally resorted
    #  to explicitly writing my own hidden input tags.  (Later note:  this is
    #  almost certainly do to my failure to properly use the library -override
    #  flag.)

    push @$html, $cgi->h2( "Propose a New Protein Encoding Gene"
                         . ( ( $covering && ! $location ) ? " Covering a Region" : "" )
                         . " in the Genome<BR />$organism ($genome)"
                         ), "\n";

    push @$html, $cgi->start_form( -method => 'post',
                                   -action => 'propose_new_peg.cgi',
                                   -name   => 'propose_new_peg'
                                 ),
                 #  The helper function ensures that values are quoted
                 hidden_input( 'user', $user ),
                 hidden_input( 'genome', $genome ),
                 hidden_input( 'function', $function ),
                 hidden_input( 'old_pre', $npre ),
                 $location ? hidden_input( 'location', $location ) : (),
                 $covering ? hidden_input( 'covering', $covering ) : ();

    my $dna = $fig->dna_seq( $genome,
                             map { join '_', $_->[0], $_->[1], $_->[2] } @loc2
                           );

    #---------------------------------------------------------------------------
    #  Now that the preliminaries are done, what did the user want?
    #---------------------------------------------------------------------------

    if ( $create )
    {
        if ( ! $start )
        {
            push @$html,
                 $cgi->h3( "<FONT Color=red>Creating a feature requires defining a "
                         . "start site. Please select one below and try again.</FONT>"
                         ), "\n";
            $create = undef;
        }
        if ( ! $user )
        {
            push @$html,
                 $cgi->h3( "<FONT Color=red>Creating a feature requires a user ID.  "
                         . "Please enter one below and try again.</FONT>"
                         ), "\n",
                 "User ID: ",
                 $cgi->textfield( -name => 'user', -size => 40 ), "<BR />\n",
            $create = undef;
        }
        if ( ! $function )
        {
            push @$html,
                 $cgi->h3( "<FONT Color=red>Creating a feature requires a defined "
                         . "function.  Please enter one below and try again.</FONT>"
                         ), "\n";
            $create = undef;
        }

        #  Did we survive the tests?

        if ( $create )
        {
            #  Do something exciting and intelligent.
            #
            #  Remember, there is nothing that forces the viewed region,
            #  which is all that is in the sequences above, to include the
            #  stop codon!  We may need to search for it.

            my $fid = create_feature( $fig, $cgi, $user, $html, $genome, \@loc2, $dna, $start,
                                      \%ignore, \%gencode, \%is_start, $function
                                    );
            push @$html,
                 $cgi->h3( "<FONT Color=#A00000>Request for new feature was successful: "
                         . HTML::fid_link( $cgi, $fid ) . "</FONT>"
                         ), "\n"  if $fid;
            push @$html,
                 $cgi->h3( "<FONT Color=#A00000>Request for new feature failed.</FONT>"
                         ), "\n"  if ! $fid;

            $start = undef if $fid;  #  Don't make it easy to create it twice.
        }
    }

    #---------------------------------------------------------------------------
    #  Let the user define or change the proposed function
    #---------------------------------------------------------------------------

    push @$html,
         $function ? $cgi->h3( ( $create ? "Created" : "Current" ) . " function: ". html_esc($function) ) . "\n"
                   : (),
         'To ' . ( $function ? 'change the' : 'define a' ) . " function, enter one here:<BR />\n",
         $cgi->textfield( -name => 'newfunction', -size => 100 ), "<BR />\n",
         ( ($blastp && $start) ? "or select one with a radio button in the blast search results\n" : () ),
         "<P />\n";

    #---------------------------------------------------------------------------
    #  Blast proposed sequence against compete genomes?
    #---------------------------------------------------------------------------

    my ( $depth, $hsps );
    if ( $blastp && $start )
    {
        ( $depth, $hsps ) = blast_orf_region( $fig, $cgi, $html, $dna, $start,
                                              \%ignore, \%gencode, $blast_pad, $c3
                                            );
    }
    elsif ( $blastp )
    {
        push @$html, $cgi->h3( '<font color=red>BLASTP analysis requires '
                             . 'selecting a start site</font>'
                             ), "\n";
    }

    #---------------------------------------------------------------------------
    #  Let the user adjust the amount of DNA displayed
    #---------------------------------------------------------------------------

    push @$html,
         'Show ', $cgi->textfield( -name => 'npre',  -size => 4, -value => $npre, -override => 1 ),
         " upstream nucleotides<BR />\n",
         'Show ', $cgi->textfield( -name => 'npost', -size => 4, -value => $npost, -override => 1 ),
         " downstream nucleotides<p />\n";

    #---------------------------------------------------------------------------
    #  Action buttons
    #---------------------------------------------------------------------------

    push @$html,
         "<TABLE>\n",
         "  <TR><TD Align=center>",
         $cgi->submit('update'),
         "</TD><TD>display with current selections and parameters.",
         ( $blastp && $start ? "  <FONT Color=#C00000>Blast resuts will be lost.</FONT>" : () ),
         "</TD></TR>\n",
         "  <TR><TD Align=center>or</TD><TD></TD></TR>\n",
         "  <TR><TD Align=center>",
         $cgi->submit('blastp'),
         "</TD><TD>search the selected open reading frame (with an extra ",
         $cgi->textfield( -name => 'blast_pad', -size => 3, -value => $blast_pad),
         " triplets on each side) against completed genomes.</TD></TR>\n",
         "  <TR><TD Align=center>or</TD><TD></TD></TR>\n",
         "  <TR><TD Align=center>",
         $cgi->submit('create'),
         "</TD><TD>a new feature from the currently selected open reading frame.</TD></TR>\n",
         "</TABLE>\n";

    #---------------------------------------------------------------------------
    #  What are the locations of existing features in the window?
    #---------------------------------------------------------------------------

    my @f_map = feature_map( $fig, $genome, \@loc2 );

    #---------------------------------------------------------------------------
    #  What Shine-Dalgarno sites?
    #---------------------------------------------------------------------------

    my @sd_map = shine_dalgano_map( $dna );

    #---------------------------------------------------------------------------
    #  Nucleotide triplets and their attributes
    #---------------------------------------------------------------------------

    my $c_num = 0;
    my @dna2 = map { my $clr = shift @$_;               # Put into table cells
                     "\t<TD" . ( $clr ? " BgColor=$clr" : "" ) . ">"
                   . join( "<BR />", @$_ )
                   . "</TD>\n"
                   }
               map { $c_num++;                          # Translate and decorate them
                     my $cdn = uc $_;
                     my $aa  = $gencode{ $cdn } || 'X';
                     my $typ = $aa eq "*"                    ? "-"
                             : $is_start{ $cdn }             ? "+"
                             : $c_num == 1 && $p1_contig_end ? "+"
                             : $c_num <= $c1                 ? "."
                             : $c_num >  $c2                 ? "."
                             :                                 " ";
                     my @cvr = $depth ? @{ shift @$depth } : ();
                     my $clr = $typ eq "-" ? "#FF8888"  #  Red stops
                             : $typ eq "+" ? "#88FF88"  #  Green starts
                             : $cvr[0] > 0 ? "#FFFF66"  #  Yellow for matches
                             : $typ eq "." ? "#DDDDDD"  #  Gray outside of focus
                             :               '#FFFFFF'; #  White in match region
                     $clr = blend( $clr, '#0080FF', ( 0.75 * shift @sd_map ) );
                     my $ctl = $typ eq "-" ? ignore_box( $c_num, \%ignore )
                             : $typ eq "+" ? start_button( $c_num, $start )
                             :               "&nbsp;";
                     [ $clr, @cvr, $aa, $_, (shift @f_map), $ctl ]
                   }
               $dna =~ m/.../g;                      #  Break DNA into triplets

    #---------------------------------------------------------------------------
    #  Display the sequence in a table
    #---------------------------------------------------------------------------
    #  Describe the controls in the table

    push @$html, "<P />Click a radio button to <b>select</b> a protein start location ",
                 "(edit allowed start codons below).<BR />\n",
                 "Click a checkbox to <b>ignore</b> that stop codon (or edit the ",
                 "genetic code below).<P />\n";

    #  In the case of BLAST results, the extra information should be explained

    if ( $depth )
    {
#  Longer text
#
#  The two numbers above the amino acids provide a site-by-site summary of the
#  BLASTP results.  The top number is the number of blast matches that include
#  that amino acid position within the matching region (within the HSP).  (When
#  this number is greater than zero, the cell is colored yellow.)  The lower
#  number is the number of blast matches in which the subject sequence WOULD
#  cover the codon IF the match had extended (without gaps) all the way to the
#  end of the subject sequence (without additional gaps).  If it is much larger
#  than the top number, it suggests that the DNA region only matches part of the
#  database proteins.  This could be due to low similarity, truncation or a
#  frameshift.

        push @$html, <<'DEPTH_TEXT';
The two numbers above the amino acids are a site-by-site summary of the BLASTP
results.  The top value is the number of blast matches overlapping the amino
acid (nonzero values are yellow).  The bottom value is the number of blast
matches that WOULD overlap the triplet IF the match continued without gaps to
the end of the database sequence.  Blue shading indicates potential ribosome
binding sites.<P />
DEPTH_TEXT
    }

    my $ncol = 30;
    push @$html, start_button( 0, -1 ) . " Cancel start selection\n",
                 "<TABLE Style='font-family: Courier, monospace'>\n";

    for ( my$i0 = 0; $i0 < @dna2; $i0 += $ncol )
    {
        push @$html, "  <TR Align=center VAlign=top>\n",
                     join( "", @dna2[$i0 .. ($i0 + $ncol - 1)] ),
                     "  </TR>\n";
    }

    push @$html, "</TABLE>\n",
                 start_button( 0, -1 ) . " Cancel start selection<P />\n";

    #---------------------------------------------------------------------------
    #  Action buttons
    #---------------------------------------------------------------------------

    push @$html,
         "<TABLE>\n",
         "  <TR><TD Align=center>",
         $cgi->submit('update'),
         "</TD><TD>display with current selections and paramters.",
         ( $blastp && $start ? "  <FONT Color=#C00000>Blast resuts will be lost.</FONT>" : () ),
         "</TD></TR>\n",
         "  <TR><TD Align=center>or</TD><TD></TD></TR>\n",
         "  <TR><TD Align=center>",
         $cgi->submit('blastp'),
         "</TD><TD>search the selected open reading frame against completed genomes.</TD></TR>\n",
         "  <TR><TD Align=center>or</TD><TD></TD></TR>\n",
         "  <TR><TD Align=center>",
         $cgi->submit('create'),
         "</TD><TD>a new feature from the currently selected open reading frame.</TD></TR>\n",
         "</TABLE>\n";

    #---------------------------------------------------------------------------
    #  Edit the start codon list
    #---------------------------------------------------------------------------

    #  Format start codon and genetic code editors as two columns of a table:

    push @$html, "<TABLE><TR><TD Align=center>\n";

    push @$html, $cgi->h3( "Edit Allowed Start Codons" ), "\n",
                 "<TABLE>\n",

    my ( $nt1, $nt2, $nt3, $codon );
    foreach $nt1 ( qw( T C A G ) )          # First
    {
        push @$html, "  <TR>\n";
        foreach $nt2 ( qw( T C A G ) )      # Second
        {
            push @$html,
                 "    <TD>",
                 join( "&nbsp;&nbsp;<BR />",
                       map { $codon = $nt1 . $nt2 . $_;
                             $cgi->checkbox( -name     => 'is_start',
                                             -value    => $codon,
                                             -checked  => $is_start{ $codon },
                                             -label    => $codon,
                                             -override => 1
                                           )
                           } qw( T C A G )
                     ),
                 "</TD>\n";
        }
        push @$html, "  </TR>\n";
    }

    push @$html, "</TABLE>\n";

    #  End start codon cell, add a spacer cell, and start genetic code cell

    push @$html, "</TD>\n",
                 "<TD Width=40></TD>\n",
                 "<TD Align=center>\n";

    #---------------------------------------------------------------------------
    #  Edit the genetic code
    #---------------------------------------------------------------------------
    #  Originally, only known deviations from the standard code were allowed:
    #
    #  my %code_alts = ( AAA => [ qw( K N     ) ], # K
    #                    AGA => [ qw( R G S * ) ], # R
    #                    AGG => [ qw( R G S * ) ], # R
    #                    ATA => [ qw( I M     ) ], # I
    #                    CTA => [ qw( L T     ) ], # L
    #                    CTC => [ qw( L T     ) ], # L
    #                    CTG => [ qw( L S T   ) ], # L
    #                    CTT => [ qw( L T     ) ], # L
    #                    TAA => [ qw( * Q Y   ) ], # *
    #                    TAG => [ qw( * Q     ) ], # *
    #                    TGA => [ qw( * C W   ) ], # *
    #                  );
    #
    #                  @aa = @{ $code_alts{ $codon } || [ $gencode{ $codon } || 'X' ] };
    #

    my @aa = qw( A C D E F G H I K L M N P Q R S T V W Y * U X );

    push @$html, $cgi->h3( "Edit Genetic Code" ), "\n",
                 "<TABLE>\n",

    my ( $nt1, $nt2, $nt3, $codon, $vals, $lbls, $dflt );
    foreach $nt1 ( qw( T C A G ) )          # First
    {
        push @$html, "  <TR>\n";
        foreach $nt2 ( qw( T C A G ) )      # Second
        {
            push @$html,
                 "    <TD>",
                 join( "&nbsp;&nbsp;<BR />",
                       map { $codon = $nt1 . $nt2 . $_;
                             $vals = [ map { "$codon.$_" } @aa ];
                             $lbls = { map { ( "$codon.$_", $_ ) } @aa  };
                             $dflt = "$codon.$gencode{$codon}";
                             "$codon => " .
                             $cgi->popup_menu( -name     => 'code_opts',
                                               -values   => $vals,
                                               -labels   => $lbls,
                                               -default  => $dflt,
                                               -override => 1
                                             )
                           } qw( T C A G )
                     ),
                 "</TD>\n";
        }
        push @$html, "  </TR>\n";
    }
    push @$html, "</TABLE>\n";

    push @$html, "</TD></TR></TABLE>\n";

    #---------------------------------------------------------------------------
    #  Action buttons
    #---------------------------------------------------------------------------

    push @$html,
         "<TABLE>\n",
         "  <TR><TD Align=center>",
         $cgi->submit('update'),
         "</TD><TD>display with current selections and paramters.",
         ( $blastp && $start ? "  <FONT Color=#C00000>Blast resuts will be lost.</FONT>" : () ),
         "</TD></TR>\n",
         "  <TR><TD Align=center>or</TD><TD></TD></TR>\n",
         "  <TR><TD Align=center>",
         $cgi->submit('blastp'),
         "</TD><TD>search the selected open reading frame against completed genomes.</TD></TR>\n",
         "  <TR><TD Align=center>or</TD><TD></TD></TR>\n",
         "  <TR><TD Align=center>",
         $cgi->submit('create'),
         "</TD><TD>a new feature from the currently selected open reading frame.</TD></TR>\n",
         "</TABLE>\n";

    #---------------------------------------------------------------------------
    #  End the FORM
    #---------------------------------------------------------------------------

    push @$html, $cgi->end_form, "\n";
}


#-------------------------------------------------------------------------------
#  Some helper functions
#-------------------------------------------------------------------------------
#  Produce an HTML hidden input tag:
#-------------------------------------------------------------------------------
sub hidden_input
{   my ( $name, $value ) = @_;
    $name ? "<INPUT Type=hidden Name=" . quoted_value( $name )
            . ( defined( $value ) ? " Value=" . quoted_value( $value ) : "" )
            . ">"
          : wantarray ? () : ""
}

#-------------------------------------------------------------------------------
#  Make quoted strings for use in HTML tags:
#-------------------------------------------------------------------------------
sub quoted_value
{   my $val = shift;
    $val =~ s/\&/&amp;/g;
    $val =~ s/"/&quot;/g;
    qq("$val")
}

#-------------------------------------------------------------------------------
#  Quote HTML text so that it displays correctly:
#-------------------------------------------------------------------------------
sub html_esc
{   my $val = shift;
    $val =~ s/\&/&amp;/g;
    $val =~ s/\</&lt;/g;
    $val =~ s/\>/&gt;/g;
    $val
}

#-------------------------------------------------------------------------------
#  Build the text for an ignore stop codon checkbox
#-------------------------------------------------------------------------------
sub ignore_box
{  my ( $c_num, $ignore ) = @_;
     "<input type=checkbox name=ignore value=$c_num"
   . ( $ignore->{ $c_num } ? " checked" : "" )
   . ">"
}

#-------------------------------------------------------------------------------
#  Build the text for an start codon selection button
#-------------------------------------------------------------------------------
sub start_button
{  my ( $c_num, $start ) = @_;
     "<input type=radio name=start value=$c_num"
   . ( $c_num == $start ? " checked" : "" )
   . ">"
}


#==============================================================================
#  Create a new feature
#
#  $fid = create_feature( $fig, $cgi, $user, $html, $genome, $loc2, $dna, $start,
#                         $ignore, $gencode, $is_start, $function
#                       )
#==============================================================================

sub create_feature
{
    my ( $fig, $cgi, $user, $html, $genome, $loc2, $dna, $start, $ignore,
         $gencode, $is_start, $function
       ) = @_;

    #---------------------------------------------------------------------------
    #  The start codon becomes a methionine?
    #---------------------------------------------------------------------------

    my $nt1 = 3 * ( $start - 1 );          # Zero-based numbering into $dna
    my $init = uc substr( $dna, $nt1, 3 );
    my @pep = ( $is_start->{ $init } ? "M" : $gencode->{ $init } || 'X' );

    #---------------------------------------------------------------------------
    #  We divide the rest of the DNA into triplets and translate to a stop:
    #---------------------------------------------------------------------------

    $dna = substr( $dna, $nt1+3 );
    my $c_num = $start + 1;    #  We need triplet numbers for %ignore
    my $done = 0;              #  Flag for stop found (we could run out of DNA)

    foreach ( map { $gencode->{ uc $_ } || 'X' } $dna =~ m/.../g )  #  Translate
    {
        if    ( $_ ne "*" )           { push @pep, $_ }      #  Amino acid
        elsif ( $ignore->{ $c_num } ) { push @pep, "X" }     #  Ingnored stop
        else                          { $done = 1; last }    #  Stop
        $c_num++;                                            #  Count triplets
    }

    #---------------------------------------------------------------------------
    #  Did we run out of triplets without a stop?
    #---------------------------------------------------------------------------

    if ( ! $done )
    {
        #  Is there more DNA sequence available?

        my ( $contig, $n1, $n2, $dir, $len, $clen ) = @{ $loc2->[-1] };
        my $n3 = $n2;

        while ( ! $done )
        {
            my $newdna = "";
            my $dn = 900;                             # Get 900 more nucleotides

            if ( $dir > 0 )
            {
                $dn  = $clen - $n3 if ( $n3 + $dn ) > $clen;  #  Truncate if too long
                $dn -= $dn % 3;                               #  Make even triplets
                if ( $dn < 3 ) { $done = 1; last }            #  Is there any?
                $newdna = $fig->dna_seq( $genome, ( join '_', $contig, $n3+1, $n3+$dn ) );
                $n3 += $dn;
            }
            else
            {
                $dn  = $n3 - 1 if $dn >= $n3;         # Truncate if too long
                $dn -= $dn % 3;                       # Make even triplets
                if ( $dn < 3 ) { $done = 1; last }    # Is there any?
                $newdna = $fig->dna_seq( $genome, ( join '_', $contig, $n3-1, $n3-$dn ) );
                $n3 -= $dn;
            }

            foreach ( map { $gencode->{ uc $_ } || 'X' } $newdna =~ m/.../g )  # Translate
            {
                if ( $_ ne "*" ) { push @pep, $_ }       # Add to peptide
                else             { $done = 1; last }     # Stop
            }
        }
    }

    my $pep_seq = join( "", @pep );

    #---------------------------------------------------------------------------
    #  We have found the protein end.  Time to build the location description:
    #  @$loc2 is the description of the DNA visible on the page.  We should
    #  extend it (as @raw) to the end of the contig, in case the end of the
    #  protein is not visible.
    #---------------------------------------------------------------------------

    my @raw = @$loc2;
    my ( $contig, $n1, $n2, $dir, $len, $clen ) = @{$raw[-1]};
    if ( $dir > 0 ) { $len += $clen - $n2; $n2   = $clen; }
    else            { $len += $n2   - 1;   $n2   = 1;     }
    $raw[-1] = [ $contig, $n1, $n2, $dir, $len, $clen ];

    my $nt2 = $nt1 + 3 * length( $pep_seq ) - 1;
    my @loc = ();
    my ( $n_min, $n_max, $p1, $p2 );

    # $n_max is the highest coordinate in $dna covered so far

    $n_max = 0;
    while ( $n_max <= $nt1 )
    {
        return undef if ! @raw;
        ( $contig, $n1, $n2, $dir, $len, $clen ) = @{ shift @raw };
        return undef if ! $contig;
        $n_min  = $n_max;
        $n_max += $len;
    }
    $p1 = $n1 + $dir * ( $nt1 - $n_min );

    while ( $n_max <= $nt2 )
    {
        push @loc, join( '_', $contig, $p1, $n2 );
        ( $contig, $n1, $n2, $dir, $len, $clen ) = @{ shift @raw };
        return undef if ! $contig;
        $p1 = $n1;
        $n_min  = $n_max;
        $n_max += $len;
    }

    $p2 = $n1 + $dir * ( $nt2 - $n_min );

    #  The terminator codon is a special case.  It was not added above because
    #  we don't want to fail if we cannot get it.  (An alternative, perhaps
    #  simpler, strategy would have been to push the terminator on the peptide,
    #  then cut it off after computing the length of the coding region.)

    if ( $dir > 0 ) { $p2 += 3 if $p2 + 3 <= $clen }
    else            { $p2 -= 3 if $p2     >  3     }

    push @loc, join( '_', $contig, $p1, $p2 );
    my $location = join ',', @loc;

    #  We now have the location description.
    #
    #  We should never recreate an existing feature.  Locate features that
    #  overlap the end of this one:

    my ( $c, $beg, $end ) = $loc[-1] =~ m/^(.+)_(\d+)_(\d+)$/;
    if ( $beg > $end )  { ( $beg, $end ) = ( $end, $beg ) }

    #  The discarded return values are min_coord and max_coord of features:

    my ( $features, undef, undef ) = $fig->genes_in_region( $genome, $c, $beg, $end );

    #  Filter by type and locate the overlapping features:

    my @feat_and_loc = map  { [ $_, scalar $fig->feature_location( $_ ) ] }
                       grep { /\.peg\.\d+$/ }          # Same type
                       @$features;                     # Overlapping features

    my @same_loc = map  { $_->[0] }                    # Save the fid
                   grep { $_->[1] eq $location }       # Same location?
                   @feat_and_loc;                      # Located features

    if ( @same_loc )
    {
        push @$html,
             "<H3><FONT Color=red>This feature already exists: "
           . HTML::fid_link( $cgi, $same_loc[0] ) . "</FONT></H3>\n";
        return undef;
    }

    #  Is the proposed feature the same except for the start location?  Find
    #  out by setting first segment start to 0 (this does not handle locations
    #  that add or remove whole segments -- this behavior that might be good
    #  for alternative slicing, but it makes fixing frameshifts more tedious):

    my $loc0 = zero_start( $location );
    my @same_but_start = map  { $_->[0] }                        # Save the fid
                         grep { zero_start( $_->[1] ) eq $loc0 } # Same ending?
                         @feat_and_loc;                          # Located features

    my $change_start = $cgi->param( 'change_start' ) || undef;

    if ( ! $change_start && @same_but_start )
    {
        push @$html,
             "<H3><FONT Color=red>This request differs only in start location from "
           . "one or more existing feature(s): ",
             join( ' &amp; ', map { HTML::fid_link( $cgi, $_ ) } @same_but_start ),
             "<BR />\nTo create the new feature, "
           . "choose a radio button below and click 'create' again.</FONT></H3>\n"
           . "<INPUT Type=radio Name=change_start Value=keep_both> Keep both features<BR />\n"
           . "<INPUT Type=radio Name=change_start Value=replace> Replace existing feature(s)<BR />\n";
        return undef;
    }

    #---------------------------------------------------------------------------
    #  We have everything that we need to create a peg.
    #---------------------------------------------------------------------------

    my $aliases = '';
    my $fid = $fig->add_feature( $user, $genome, 'peg', $location, $aliases, $pep_seq );
    if ( ! $fid )
    {
        push @$html,
             "<H3><FONT Color=red>Call to add_feature failed.  More information "
           . "might be available in the WWW server log file.</FONT></H3>\n";
        return undef;
    }

    #  The new feature was successfully created.  Was there a request to remove
    #  one or more overlapping features?

    if ( @same_but_start && ( $change_start =~ m/^replace$/i ) )
    {
        foreach my $old_fid ( @same_but_start )
        {
            $fig->delete_feature( $user, $old_fid );
            push @$html,
                 "<H3><FONT Color=#A00000>Deleted feature $old_fid</FONT></H3>\n";
        }
    }

    #  On the PubSEED, assign_function is failing immediately after the
    #  feature is created.  Let's try a loop with a timer.

    my $assigned = 0;
    foreach my $t ( 0.25, 0.25, 0.5, 1, 2, -1 )
    {
        last if ( $assigned = $fig->assign_function( $fid, $user, $function ) );
        last if ( $t <= 0 );
        print STDERR "assign_function failed for '$fid'\n. Trying again in $t seconds.\n";
        Time::HiRes::sleep $t;
    }
    if ( ! $assigned )
    {
        push @$html,
             "<H3><FONT Color=red>Call to assign_function failed.  More information "
           . "might be available in the WWW server log file.</FONT></H3>\n";
    }

    return $fid;
}


sub zero_start
{
    my @loc = split /,/, shift;
    $loc[0] =~ s/_\d+_(\d+)$/_0_$1/;
    join ',', @loc
}


#===============================================================================
#  What are the features in the window?
#===============================================================================
#  The analysis is carried out segment-by-segment in multi-segment locations.
#  The maps of the segments are simply concatenated.
#
#  |------------------------------------|----------------|---...  window
#  |------------------------------------|                         first segment
#             contig_n1_n2              |----------------|        second segment
#                                          contig_n1_n2  |---...  etc.
#
#
#  Forward oriented segment ( n1 < n2, dir = 1 ):
#
#  0   b1-n1   e1-n1  e2-n1  b2-n1    len-1  coordinates in @ends
#  |     |       |      |      |        |
#  |----->>>>>>>>>------<<<<<<<<--------|    features mapped on segment
#  n1    |       |      |      |        n2   segment coordinates in contig
#        b1      e1     e2     b2            2 feature locations in contig
#
#
#  Reverse oriented segment ( n1 > n2, dir = -1 ):
#
#  0   n1-b1   n1-e1  n1-e2  n1-b2    len-1  coordinates in @ends
#  |     |       |      |      |        |
#  |----->>>>>>>>>------<<<<<<<<--------|    features mapped on segment
#  n1    |       |      |      |        n2   segment coordinates in contig
#        b1      e1     e2     b2            2 feature locations in contig
#
#  So any location loc maps to: dir * ( loc - n1 ).
#-------------------------------------------------------------------------------

sub feature_map
{   my ( $fig, $genome, $loc2 ) = @_;
    my $string = "";   #  Catenate each segment to the end

    foreach my $segment ( @$loc2 )
    {
        my ( $contig, $n1, $n2, $dir, $len ) = @$segment;
        my ( $min, $max ) = ( $dir > 0 ) ? ( $n1, $n2 ) : ( $n2, $n1 );
        my ( $features ) = $fig->genes_in_region( $genome, $contig, $min, $max );

        #  Mark the end points of features in the @ends array.  These can then
        #  be scanned sequentially to build the image.  Elements in @ends are
        #  counts of the following event types:
        #
        #     [ start_rightward, end_rightward, start_leftward, end_leftward ]

        my @ends;
        $#ends = $len - 1;   #  Force the array to cover the whole sequence
        foreach my $fid ( @$features )
        {
            my ( $contig1, $beg, $end ) = $fig->boundaries_of( scalar $fig->feature_location( $fid ) );
            next if $contig1 ne $contig;

            my $rightward = ( $dir > 0 ) ? ( ( $beg < $end ) ? 1 : 0 )
                                         : ( ( $beg < $end ) ? 0 : 1 );
            my ( $s, $e ) = $rightward ? ( $beg, $end ) : ( $end, $beg );

            $s = $dir * ( $s - $n1 );  #  left end coordinate on map
            $e = $dir * ( $e - $n1 );  #  right end coordinate on map
            next if ( $s >= $len ) || ( $e < 0 );

            if ( $s < 0 ) { $s = 0 }
            $ends[ $s ]->[ $rightward ? 0 : 2 ]++;

            if ( $e >= $len ) { $e = $len -1 }
            $ends[ $e ]->[ $rightward ? 1 : 3 ]++;
        }

        #  Okay, the start and end events are marked.  Now for a text string.
        #  Symbols in the map:
        #     .  No feature
        #     >  Left-to-right feature
        #     <  Right-to-left feature
        #     =  Overlapping left-to-right and right-to-left features

        my @map = ();
        my ( $nright, $nleft ) = ( 0, 0 );
        foreach ( @ends )
        {
            $_ ||= [];
            $nright += $_->[0];
            $nleft  += $_->[2];
            push @map, $nright ? ( $nleft ? "=" : ">" )
                               : ( $nleft ? "<" : "." );
            $nright -= $_->[1];
            $nleft  -= $_->[3];
        }

        $string .= join "", @map;
    }

    wantarray ? $string =~ m/.../g : [ $string =~ m/.../g ]
}


#==============================================================================
#  Blast the select orf and surrounding sequence against complete genomes
#
#  ( $depth, $hsps ) = blast_orf_region( $fig, $cgi, $html, $dna, $start,
#                                        $ignore, $gencode, $blast_pad, $c3
#                                      )
#
#  @$depth is an array of couples, [ depth_matched, depth_shadowed ].
#  The first number is the number of blast matches that include that
#  codon (the codon is in the interval m1-m2 below).  The second number
#  is the number of blast matches for which the subject sequence would
#  cover the codon IF the match were continued all the way to the ends
#  of the subject sequence (the codons in the interval p1-p2 below).
#
#  @$hsps is an array of HSPs with the following fields:
#
#      [ qid qdef qlen sid sdef slen scr e_val n_seq e_valn mat id pos gap frame q1 q2 qseq s1 s2 sseq ]
#
#  Some of the coordinate systems to juggle (coordinates are 1-based,
#  but the data arrays are all 0-based):
#
#                      start
#  1            p1  cdn1 | m1          m2         p2       c3
#  |------------|----|---|-|-----------|----------|--------| displayed seq
#               |    |   | |           |          |
#               |    |   |-|-----------|---|      |          selected orf
#               |    |     |           |          |
#               |    |-----=============------|   |          query & match
#               |    1     q1         q2     qlen |
#               |----------=============----------|          subject & match
#               1          s1         s2         slen
#
#  (m1,m2) = matching coord in displayed sequence = (cdn1+q1-1, cdn1+q2-1)
#  (p1,p2) = region shadowed by subject length = (cdn1+q1-s1, cdn1+q2-1+(slen-s2))
#                                              = (m1-(s1-1), m2+(slen-s2))
#
#  At each location along the displayed sequence, record 4 event types:
#
#     [ match_start, match_end, shadow_start, shadow_end ]
#
#  The depth of coverage will then be computed by scanning along the
#  finished array of events.
#==============================================================================

sub blast_orf_region
{
    my ( $fig, $cgi, $html, $dna, $start, $ignore, $gencode, $blast_pad, $c3 ) = @_;

    my ( $cdn1, @seq, $pad, $aa, $c_num );
    my @aa = map { $gencode->{ uc $_ } || 'X' } $dna =~ m/.../g;

    #---------------------------------------------------------------------------
    # The blast_pad is translated unconditionally:
    #---------------------------------------------------------------------------

    $cdn1 = $start - $blast_pad;
    $cdn1 = 1 if $cdn1 < 1;
    @seq = @aa[ ( $cdn1-1 ) .. ( $start-2 ) ];

    #---------------------------------------------------------------------------
    # The start codon becomes a methionine:
    #---------------------------------------------------------------------------

    push @seq, "M";

    #---------------------------------------------------------------------------
    # Next we translate to a stop, plus $blast_pad more:
    #---------------------------------------------------------------------------

    $pad = 0;
    for ( $c_num = $start + 1; ( $aa = $aa[ $c_num-1 ] ) && ( $pad < $blast_pad ); $c_num++ )
    {
        if ( $pad )
        {
            push @seq, ( ( $aa eq "*" ) && $ignore->{ $c_num } ? "X" : $aa );
            $pad++;
        }
        elsif ( $aa eq "*" )
        {
            if ( $ignore->{ $c_num } )
            {
                push @seq, "X";
            }
            else
            {
                push @seq, $aa;
                $pad++;
            }
        }
        else
        {
            push @seq, $aa;
        }
    }

    my $seq  = join( "", @seq );
    my $qlen = length( $seq );

    #---------------------------------------------------------------------------
    #  Ready to put the query in a file:
    #---------------------------------------------------------------------------

    my $qid     = "proposed";
    my $tmp_seq = "$FIG_Config::temp/run_blast_tmp_$$.seq";
    open( SEQ, ">$tmp_seq" ) || die "run_blast could not open $tmp_seq";
    print SEQ  ">$qid peg\n$seq\n";
    close SEQ;

    $ENV{"BLASTMAT"} ||= "$FIG_Config::blastmat";
    # my $blast_opt = $cgi->param( 'blast_options' ) || '';

    #---------------------------------------------------------------------------
    #  Do the BLAST and put the hits in a table
    #---------------------------------------------------------------------------

    my $sims = blast_complete( $fig, $cgi, $html, $tmp_seq );
    unlink( $tmp_seq );

    format_sims_table( $fig, $cgi, $html, $sims );

    #---------------------------------------------------------------------------
    #  Build a map of the match sites onto the displayed sequence
    #
    #  match = [ sid sdef slen scr exp mat id q1 q2 s1  s2 ]
    #             0    1    2   3   4   5   6  7  8  9  10
    #---------------------------------------------------------------------------

    #  Build an empty array up front
    my @events;
    $#events = $c3 - 1;

    foreach ( @$sims )
    {
        #  Matching region of query mapped onto display coordinates
        my ( $m1, $m2 ) = ( $cdn1 + $_->b1 - 1, $cdn1 + $_->e1 - 1 );
        #  Length of subject seqeunce mapped onto display coordinates
        my ( $p1, $p2 ) = ( $m1 - ( $_->b2 - 1 ), $m2 + ( $_->ln2 - $_->e2 ) );
        $p1 = 1   if $p1 < 1;
        $p2 = $c3 if $p2 > $c3;
        $events[ $m1-1 ]->[0]++;
        $events[ $m2-1 ]->[1]++;
        $events[ $p1-1 ]->[2]++;
        $events[ $p2-1 ]->[3]++;
    }

    #  Add the starts and report the values in element 0, subtract the ends
    #  in elements 1 and 2, and then report only element 0 (with the slice):

    my @depth = ();
    my ( $n_cov, $n_shad ) = ( 0, 0 );
    foreach ( @events )
    {
        $n_cov  += $_->[0];
        $n_shad += $_->[2];
        push @depth, [ $n_cov || ".", $n_shad || "." ];
        $n_cov  -= $_->[1];
        $n_shad -= $_->[3];
    }

    ( \@depth, $sims );
}


#==============================================================================
#  Search for a protein sequence in the complete genomes:
#
#     blast_complete( $fig, $cgi, $html, $seqfile )
#
#==============================================================================

sub blast_complete
{
    my( $fig, $cgi, $html, $seqfile ) = @_;

    my $max_e_val    =    0.01;
    my $max_per_gen  =  100;
    my $max_per_subj =    3;
    my $max_sims     = 1000;

    my @sims = ();

    my ( $db ) = grep { -s $_ } (  $FIG_Config::seed_genome_nr,
                                  "$FIG_Config::global/seed.nr"
                                );
    if ( $db && BlastInterface::verify_db( $db, "p" ) )
    {
        my $blast_opt = { maxE     => $max_e_val,
                          lcFilter =>        'T',
                          maxHSP   =>  $max_sims,
                          outForm  =>      'sim',
                          threads  =>          4
                        };
        my $sim;
        my %seen = ();
        my @md5_sims = map  { ++$seen{ $_->id2 } <= $max_per_subj ? $_ : () }
                       sort { $b->bsc <=> $a->bsc }
                       BlastInterface::blast( $seqfile, $db, 'blastp', $blast_opt );

        foreach my $md5_sim ( @md5_sims )
        {
            #  Expand md5 to fids
            push @sims, map  { my $sim = [ @$md5_sim ];  # copy
                               $sim->[1] = $_;           # fix id
                               Sim->new( $sim )          # bless it
                             }
                        grep { $fig->is_real_feature( $_ ) }
                        $fig->pegs_with_md5( $md5_sim->id2 );

            last if @sims >= $max_sims;
        }
    }
    else
    {
        my $blast_opt = { maxE     =>   $max_e_val,
                          lcFilter =>          'T',
                          maxHSP   => $max_per_gen,
                          outForm  =>        'sim',
                          threads  =>            4
                        };

        foreach my $genome ( $fig->genomes("complete") )
        {
            my $db = "$FIG_Config::organisms/$genome/Features/peg/fasta";
            next if ( ! -s $db );
            next if ( ! BlastInterface::verify_db( $db, "p" ) );

            my %seen = ();  # Limit hits per subject sequence
            push @sims, map { ( ++$seen{ $_->id2 } > $max_per_subj ) ? () : $_ }
                        BlastInterface::blast( $seqfile, $db, 'blastp', $blast_opt );
        }

        @sims = sort { $b->bsc <=> $a->bsc } @sims;
        splice @sims, $max_sims  if @sims > $max_sims;
    }

    #  Return list ordered by bit score:

    wantarray ? @sims : \@sims;
}


#==============================================================================
#  format_sims_table
#==============================================================================

sub format_sims_table
{   my ( $fig, $cgi, $html, $sims ) = @_;

    if ( ! $sims || ! @$sims )
    {
       push @$html,
            $cgi->h3('<FONT Color=#800000>No similarites were found</FONT>'),
            "\n";
       return;
    }

    push @$html, $cgi->submit('create'), " a new feature from the currently selected open reading frame.<BR />\n";

    push @$html, "<INPUT Type=radio Name=assign_from Value=''> Cancel the function selection below<BR />\n";

    my @cols = qw( s_id e_val/identity s_region q_region s_subsys s_evidence from s_def s_genome );
    my $params = { e_value         =>      0.001,
                   min_q_cov       =>      0.3,
                   min_s_cov       =>      0.3,
                   max_sims        =>   1000,
                   group_by_genome =>      1,
                   col_request     => \@cols,
                   simform         => 'propose_new_peg',
                   frombtn         => 'assign_from',
                   action          =>      0,
                 };
    push @$html, SimsTable::similarities_table( $fig, $cgi, $sims, '', $params );

    push @$html, "<INPUT Type=radio Name=assign_from Value=''> Cancel the function selection above<BR />\n";
}


#-------------------------------------------------------------------------------
#  Build the text for a role selection button
#-------------------------------------------------------------------------------

sub func_button { "<td align=center><INPUT Type=radio Name=assign_from Value=$_[0]></td>" }


#==============================================================================
#  Shine-Dalgarno score (RRGGRGGTGRTY)
#==============================================================================

sub shine_dalgano_map
{
    my ( $dna ) = @_;
    my $nmax = length( $dna ) - 1;
    my @sd = ( 0 ) x ($nmax/3);

    my @sd_scr_table =
    (
       { A =>  0.5, C => -5,   G =>  0.5, T => -5   },  # R
       { A =>  1,   C => -5,   G =>  1,   T => -5   },  # R
       { A => -5,   C => -5,   G =>  2,   T => -5   },  # G
       { A => -5,   C => -5,   G =>  2,   T => -5   },  # G
       { A =>  1.5, C => -5,   G =>  0.5, T => -5   },  # R
       { A => -5,   C => -5,   G =>  2,   T => -5   },  # G
       { A => -5,   C => -5,   G =>  2,   T => -5   },  # G
       { A => -5,   C => -5,   G => -5,   T =>  2   },  # T
       { A => -5,   C => -5,   G =>  2,   T => -5   },  # G
       { A =>  0.5, C => -5,   G =>  0.5, T => -5   },  # R
       { A => -5,   C => -5,   G => -5,   T =>  1   },  # T
       { A => -5,   C =>  0.5, G => -5,   T =>  0.5 }   # Y
    );

    for ( my $n = 0; $n <= $nmax; $n++ )
    {
        my ( $scr, $i1, $i2 ) = sd_score( substr( $dna, $n, 12 ), \@sd_scr_table );
        my $scr2 = ( $scr <  6.5 ) ? 0
                 : ( $scr < 14.5 ) ? 0.125 * ( $scr - 6.5 )
                 :                 1;
        if ( $scr2 > 0 )
        {
            my $imax = $i2;
            $imax = $nmax - $n if ( $imax > $nmax - $n );
            for ( my $i = $i1; $i <= $imax; $i++ )
            {
                my $ni = int( ( $n+$i ) / 3 );
                $sd[ $ni ] = $scr2 if ( $scr2 > $sd[ $ni ] );
            }
        }
    }

    wantarray ? @sd : \@sd;
}


sub sd_score
{
    my ( $seq, $sd_scr_table ) = @_;
    my @best = ( 0, undef, undef );
    my ( $scr, $scrmax, $i, $i1, $i2 );
    $i = 0;
    $i1 = undef;
    $scr = $scrmax = 0;

    foreach ( split //, uc $seq )
    {
        $scr += ( $sd_scr_table->[ $i ]->{ $_ } || 0 );
        
        if ( $scr >= $scrmax )
        {
            $scrmax = $scr;
            defined( $i1 ) or ( $i1 = $i );
            $i2 = $i;
        }
        elsif ( $scr < 0 )
        {
            if ( $scrmax > $best[0] ) { @best = ( $scrmax, $i1, $i2 ) }
            $scr = $scrmax = 0;
            $i1 = undef;
        }

        $i++;
    }
    if ( $scrmax > $best[0] ) { @best = ( $scrmax, $i1, $i2 ) }

    @best
}


sub blend
{
    my ( $c1, $c2, $p ) = @_;
    $c1 =~ s/^#//;
    $c2 =~ s/^#//;
    my @c1 = map { hex $_ } $c1 =~ m/../g;
    my @c2 = map { hex $_ } $c2 =~ m/../g;
    my @c3 = map { ( 1 - $p ) * $_ + $p * ( shift @c2 ) } @c1;
    sprintf "#%02x%02x%02x", @c3
}


1;
