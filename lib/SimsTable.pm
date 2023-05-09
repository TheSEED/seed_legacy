package SimsTable;

use strict;
use CGI;
use HTML;
use FIGgjo    qw( colorize_roles_in_cell_3 );
use FIGjs     qw( mouseover );   # This requires including FIG.js
#  <SCRIPT Src="./Html/css/FIG.js" Type="text/javascript"></SCRIPT>
use TableCell;
use Data::Dumper;

#===============================================================================
#
#  Build a similarities table
#
#      $html = similarities_table( $fig, $cgi, $sims, $peg, $parameters )
#
#  Parameters:
#
#      user        => $user          # gotten from $cgi if not defined
#
#  parameters that filter:
#
#      e_value     =>  $max_e_value     # E-value cut off
#      max_sims    =>  $max_sims        # Maximum number to show
#      maxE        =>  $max_e_value     # E-value cut off
#      maxN        =>  $max_sims        # Maximum number to show
#      maxP        =>  $max_e_value     # E-value cut off
#      min_q_cov   =>  $min_q_cov       # Query coverage fraction
#      min_s_cov   =>  $min_s_cov       # Subject coverage fraction
#
#  parameters that define output:
#
#      col_request => \@requested_data  # requested data (see keys below)
#      group_by_genome => $bool         # Cluster sims of genome with best match
#
#  Let's think about a very flexible sims table in which columns can be
#  specified by a keyword, or a function reference.
#
#     @columns = ( $col_def1, $col_def2, $col_def3, ... )
#
#     $col_def = [  $keyword ]
#                [  $keyword,       $column_title ]
#                [ \%value_by_simR, $column_title ]
#                [ \&function,      $column_title ]
#
#     &function( $fig, $cgi, $sim, $parameters ) should return the value to be
#                placed in the given sim table cell, and will be interpretted
#                under the rules of HTML::make_table() or
#
#  The second version allows anything, so limitations of the third form
#  should not be an issue.
#
#  Keywords with built-in functions:
#
#       q_id
#       q_def
#       q_genome
#       q_region
#       q_subsys
#       q_evidence
#       q_aliases
#
#       s_id
#       s_def
#       s_genome
#       s_region
#       s_subsys
#       s_evidence
#       s_aliases
#
#       e_val
#       identity
#       score
#       bpp = bits_per_pos = nbs
#
#       checked
#       from
#
#  Assumes that similarities are of the form returned by:
#
#    @sims = $fig->sims( $peg, $max, $cutoff, $select, $expand, $filters );
#
#===============================================================================

my $locked_color = "#ffa4a4";


sub similarities_table
{
    my( $fig, $cgi, $sims, $peg, $parameters ) = @_;
    return '' unless $fig && $sims && ref $sims eq 'ARRAY' && @$sims;

    $cgi ||= new CGI;

    $parameters && ref( $parameters ) eq 'HASH' or $parameters = {};

    my $user    = $parameters->{ user }      ||= $cgi->param('user') || '';
    my $trans   = $parameters->{ translate } ||= $user && $cgi->param('translate');
    my $sprout  = $cgi->param('SPROUT')      || 0;
    my $alter   = $user && ! $sprout;

    my $noform  = $parameters->{ noform }    ||= defined( $parameters->{ action } ) && $parameters->{ action } eq '0';
    my $action  = $parameters->{ action }    ||= 'fid_checked.cgi';
    my $simform = $parameters->{ sim_form }  ||= 'fid_checked';     # Pass in alternative
    my $frombtn = $parameters->{ frombtn }   ||= 'from';

    #  Copy the sims list and point the reference at the new list.
    #
    #  The sims as a hash key are not being unique! If they were the
    #  underlying array, I think they would be. This is going to require
    #  some ugliness. I tried using a tied RefHash or indexing by refaddr,
    #  and they continued to be indexed the same way, as though they had
    #  been unified when their contents became identical. So, I will remove
    #  duplicates.

    my @sims;
    {
        my %seen;
        @sims = grep { ! $seen{ $_ }++ } @$sims;
    }
    $sims = \@sims;

    #  Remove bad fids. This and many of the other filters below use a bare
    #  block to isolate temporary data.

    {
        my %fids = map { /^fig\|/ ? ( $_ => 1 ) : () }
                   map { ( $_->id1, $_->id2 ) }
                   @sims;

        my %good = map { $_ => 1 } $fig->is_real_feature_bulk( [ keys %fids ] );

        #  The test on id1 is an issue if a fig| sequence is externally provided
        @sims = grep { ( 1 || $_->id1 !~ /^fig\|/ || $good{ $_->id1 } )
                    && (      $_->id2 !~ /^fig\|/ || $good{ $_->id2 } )
                     }
                @sims;
    }

    #  Filter by E-value:

    my $max_e_val = $parameters->{ maxP }
                 || $parameters->{ maxE }
                 || $parameters->{ e_value }
                 || $cgi->param( 'maxP' );
    if ( $max_e_val )
    {
        @sims = grep { $_->psc <= $max_e_val } @sims;
    }

    #  Filter by query coverage:

    my $min_q_cov = $parameters->{ min_q_cov } || $cgi->param( 'min_q_cov' );
    if ( $min_q_cov )
    {
        $min_q_cov *= 0.01;
        @sims = grep { $_->ln1 * $min_q_cov <= abs( $_->e1 - $_->b1 ) + 1 } @sims;
    }

    #  Filter by subject coverage:

    my $min_s_cov = $parameters->{ min_s_cov } || $cgi->param( 'min_s_cov' );
    if ( $min_s_cov )
    {
        $min_s_cov *= 0.01;
        @sims = grep { $_->ln2 * $min_s_cov <= abs( $_->e2 - $_->b2 ) + 1 } @sims;
    }

    #  Check if any sims remain

    return ''  if ! @sims;

    #
    #  Find functions and genomes to allow collapsing identical sequences
    #  with same func.
    #
    #     $func_by_id{ $id }   =   $function
    #     $genome_by_id{ $id } = [ $genus_species, $cell_background_color ]
    #

    my %func_by_id;
    $parameters->{ func_by_id } = \%func_by_id;

    my %genome_by_id;
    $parameters->{ genome_by_id } = \%genome_by_id;

    {
        my %seen1;
        my %seen2;
        my @id1 = grep { ! $seen1{$_}++ } map { $_->id1 } @sims;
        my @id2 = grep { ! $seen2{$_}++ } map { $_->id2 } @sims;
        my @ids = ( @id2, grep { ! $seen2{$_} } @id1 );

        #  Find all the functions, making sure that they are defined
        my $func_by_idH = $fig->function_of_bulk( \@ids, 0 );

        foreach my $id ( @ids )
        {
            my $func = $func_by_idH->{ $id };
            $func_by_id{ $id }   = defined $func ? $func : '';
            $genome_by_id{ $id } = [ $fig->org_and_color_of( $id ) ];
        }
    }

    #
    #  Filter sims to one or more exemplars of a sequence, subject to
    #  having the same assigned function.
    #
    #  $parameters->{ fid_group } is a hash that maps fids to a list of subsumed fids
    #

    $parameters->{ merge_by_md5 } ||= 1;  ## Force it on for now
    if ( $parameters->{ merge_by_md5 } )
    {
        @sims = merge_identical_sims( $fig, \@sims, $parameters );
    }

    #  Are there too many sims?

    my $n_max = $parameters->{ max_sims } ||= $parameters->{ maxN };
    if ( $n_max && @sims > $n_max ) { splice @sims, $n_max }

    #  Collect all sims for a given q_id - s_id pair;

    my %same_qid_sid;
    $parameters->{ same_qid_sid } = \%same_qid_sid;
    {
        my %sims;
        my @pairs;
        foreach my $sim ( @sims )
        {
            my $pair = $sim->id1 . "\t" . $sim->id2;
            push @pairs, $pair  if ! exists $sims{ $pair };
            push @{ $sims{ $pair } }, $sim;
        }
        @sims = map { my $n = @{ $sims{$_} };
                      foreach ( @{ $sims{$_} } ) { $same_qid_sid{$_} = $n; $n = 0 }
                      @{ $sims{$_} }
                    }
                @pairs;
    }

    #  Collect all sims for a given q_id - s_genome pair:

    if ( $parameters->{ group_by_genome } || $cgi->param( 'group_by_genome' ) )
    {
        my %same_qid_sgen;
        $parameters->{ same_qid_sgen } = \%same_qid_sgen;
        my %sims;
        my @pairs;
        foreach my $sim ( @sims )
        {
            my $gen2 = $sim->id2;
            $gen2 =~ s/^fig\|(\d+\.\d+)\..+$/$1/;
            my $pair = $sim->id1 . "\t" . $gen2;
            push @pairs, $pair  if ! exists $sims{ $pair };
            push @{ $sims{ $pair } }, $sim;
        }
        @sims = map { my $n = @{ $sims{$_} };
                      foreach ( @{ $sims{$_} } ) { $same_qid_sgen{$_} = $n; $n = 0 }
                      @{ $sims{$_} }
                    }
                @pairs;
    }

    #  Get the function of the query

    my $query_func = $parameters->{ query_func } ||= $peg ? &trans_function_of( $fig, $cgi, $peg ) || '' : '';
    my $query_func_esc = html_esc( $query_func );

    #
    #  Determine function colors
    #
    #     $func_cell_data{ $sim } = [ $function_as_html, $cell_background_color ]
    #

    #  Update the list of ids and corresponding functions
    my @ids;
    {
        my %seen1;
        my %seen2;
        my @id1 = grep { ! $seen1{$_}++ } map { $_->id1 } @sims;
        my @id2 = grep { ! $seen2{$_}++ } map { $_->id2 } @sims;
        @ids = ( @id2, grep { ! $seen2{$_} } @id1 );
    }
    my @func_list = map { $func_by_id{ $_ } } @ids;
    my %func_cell_data = &FIGgjo::colorize_roles_in_cell_3( \@func_list, $query_func ); # v3
    $parameters->{ func_cell_data } = \%func_cell_data;

    my $query_rend = $func_cell_data{ $query_func } || '';

    #  Start the HTML

    my @body = ();

    #  Create the form for aligning, view annotations, getting sequences
    #  and showing regions of the selected items

    if ( ! $noform )
    {
        push @body, $cgi->start_form( -method => 'post',
                                      -target => '_blank',
                                      -action => $action,
                                      -name   => $simform
                                    ),
                    "\n";
        push @body, $cgi->hidden( -name => 'fid',       -value => $peg    ), "\n"  if $peg;
        push @body, $cgi->hidden( -name => 'SPROUT',    -value => $sprout ), "\n"  if $sprout;
        push @body, $cgi->hidden( -name => 'user',      -value => $user   ), "\n"  if $user;
        push @body, $cgi->hidden( -name => 'from_sims', -value =>  1      ), "\n";
    }

    #  Figure out the columns

    my @columns;
    my $col_request = $parameters->{ col_request };
    if ( $col_request && ref $col_request eq 'ARRAY' && @$col_request )
    {
        @columns = &process_col_request( $cgi, $col_request, $parameters );
    }
    if ( ! @columns )
    {
        $col_request = [ qw( checked s_id e_val/identity s_region q_region from s_subsys s_evidence s_def s_genome ) ];
        push @$col_request, 's_aliases'  if $parameters->{ show_alias };
        @columns = &process_col_request( $cgi, $col_request, $parameters );
    }

    return '' if ! @columns;  # Actually this situation would be very bad

    #  Will there be checkboxes?

    my $check_boxes = grep { /^checked/ } @$col_request;

    #  Some submit buttons

    if ( $check_boxes )
    {
        push @body, "For Selected (checked) sequences:\n";
        push @body, $cgi->submit( -name => 'align' ) . "\n";
        push @body, $cgi->submit( -name => 'lock_annotations',   -value => 'lock annotations' )   . "\n"  if $alter;
        push @body, $cgi->submit( -name => 'unlock_annotations', -value => 'unlock annotations' ) . "\n"  if $alter;
        push @body, $cgi->submit( -name => 'view annotations' ) . "\n";
        push @body, $cgi->submit( -name => 'get sequences' ) . "\n";
        push @body, $cgi->submit( -name => 'show regions' ) . "\n";
    }

    #  Some actions require a user

    if ( $user && $check_boxes )
    {
        my $assign_help = "Html/help_for_assignments_and_rules.html";
        push @body, "<TABLE Width=100%><TR>\n",
                    "<TD>" . $cgi->submit('assign/annotate') . "</TD>\n",
                    qq(<TD NoWrap Width=1%><A Href="$assign_help" Target="SEED_or_SPROUT_help">Help on Assignments, Rules, and Checkboxes</A></TD>\n),
                    "</TR></TABLE>\n";

        if ( $trans )
        {
            push @body, $cgi->submit('add rules'),   "\n";
            push @body, $cgi->submit('check rules'), "\n";
        }
    }

    push @body, $cgi->br, "\n";

    #  Add the query sequence checkbox

    if ( $peg )
    {
        push @body, $cgi->checkbox( -name     => 'checked',
                                    -value    => $peg,
                                    -override => 1,
                                    -checked  => 1,
                                    -label    => ''
                                  );
        push @body, $trans ? ' ASSIGN to/Translate from/SELECT current PEG' :
                    $user  ? ' ASSIGN to/SELECT current PEG'                :
                             ' SELECT current PEG';

        push @body, $cgi->br, "\n";
    }

    #  Create radio buttons (the "from" buttons):

    my ( $from_form, $from_query, @from );
    ( $from_form, $from_query, @from ) = $cgi->radio_group( -name     => $frombtn,
                                                            -nolabels => 1,
                                                            -override => 1,
                                                            -values   => [ "", $peg, map { $_->id2 } @sims ]
                                                          );
    $parameters->{ from_buttons } = \@from;

    #  Place the manual and current peg annotate from buttons:

    if ( $user && $check_boxes )
    {
        if ( $trans )
        {
            push @body, "ASSIGN/annotate with form: $from_form<BR />\n";
            push @body, "<TABLE><TR><TD Style='white-space: nowrap'>ASSIGN from/Translate to current PEG: $from_query = </TD><TD>$query_rend->[0]</TD></TR></TABLE>\n" if $query_func;
        }
        else
        {
            push @body, "ASSIGN/annotate with form: $from_form<BR />\n";
            push @body, "<TABLE><TR><TD Style='white-space: nowrap'>ASSIGN from current PEG: $from_query = </TD><TD>$query_rend->[0]</TD></TR></TABLE>\n" if $query_func;
        }
    }

    #  Add the buttons for check all and uncheck all.

    if ( $user && $check_boxes )
    {
        push @body, $cgi->br,
                    HTML::java_buttons_ext( $simform, 'checked' ),
                    $cgi->br, $cgi->br, "\n";
    }

    #  Start the similarity table with header row

    my $col_hdrs = [ map { $_->[1] } @columns ];

    #  Convert the column data request to a hash of the values for the column

    my @columns_data = map { produce_column_data( $fig, $cgi, $_->[0], \@sims, $parameters ) }
                       @columns;

    my $rows = [];
    foreach my $sim ( @sims )
    {
        my @data = map  { my $cell = $_->[0];
                          $cell->set_attribute( 'Rowspan' => $_->[1] ) if $_->[1] != 1;
                          $cell;
                        }
                   grep { $_ && $_->[1] }
                   map  { $_->{ $sim } }
                   @columns_data;

        my @row = map { $_->as_text_tag } @data;

        push @$rows, \@row;
    }

    push @body, HTML::make_table( $col_hdrs, $rows );

    push @body, $cgi->end_form, "\n" if ! $noform;

    join( '', @body );
}


#-------------------------------------------------------------------------------
#  Filter sims to one or more exemplars of a sequence, subject to
#  having the same assigned function.
#
#     @sims = merge_identical_sims( $fig, $sims, $parameters );
#
#  $parameters->{ fid_group } is associated with a hash that maps ids to the
#  others that they represent.
#-------------------------------------------------------------------------------
sub merge_identical_sims
{
    my ( $fig, $sims, $parameters ) = @_;

    my $func_by_id   = $parameters->{ func_by_id };
    my $genome_by_id = $parameters->{ genome_by_id };

    my @id1;
    my @id2;
    my @ids;
    {
        my %seen1;
        my %seen2;
        @id1 = grep { ! $seen1{$_}++ } map { $_->id1 } @$sims;
        @id2 = grep { ! $seen2{$_}++ } map { $_->id2 } @$sims;
        @ids = ( @id2, grep { ! $seen2{$_} } @id1 );
    }

    my %keep_gid = ( '' => 1 );

    #  Keep unidentified genomes
    foreach my $id ( @ids )
    {
        my $gs_color = $genome_by_id->{ $id };
        if ( ! $gs_color->[0] )
        {
            my $gid = FIG::genome_of($id);
            $keep_gid{ $gid } = 1  if $gid;
        }
    }

    my %fid_grp;
    $parameters->{ fid_group } = \%fid_grp;

    #  Keep genome of query
    foreach ( @id1 )
    {
        my $gid = FIG::genome_of($_);
        $keep_gid{ $gid } = 3 if $gid;
    }

    #  Find the md5 of each id2
    my $md5_of_fid = $fig->md5_of_peg_bulk( \@id2 );

    #  Possible merge groups
    my $gid;
    my %id2s_by_md5;
    foreach ( @id2 )
    {
        my $md5 = $md5_of_fid->{$_};
        if    ( $md5 )                      { push @{ $id2s_by_md5{$md5} }, $_ }
        elsif ( $gid = FIG::genome_of($_) ) { $keep_gid{ $gid } ||= 1 }
    }

    #  If an md5 occurs more than once in a genome, keep the genome
    foreach ( keys %id2s_by_md5 )
    {
        next unless @{ $id2s_by_md5{$_} } > 1;

        my %cnt;
        foreach ( @{ $id2s_by_md5{$_} } )
        {
            my $gid = FIG::genome_of($_) || '';
            $cnt{ $gid }++ if $gid;
        }

        foreach ( grep { $cnt{$_} > 1 } keys %cnt ) { $keep_gid{ $_ } = 2 }
    }

    #  Separate by function
    my @group;
    my @unres;
    foreach ( keys %id2s_by_md5 )
    {
        my %func;
        foreach ( @{ $id2s_by_md5{$_} } )
        {
            push @{ $func{ $func_by_id->{$_} } }, $_;
        }

        foreach ( keys %func )
        {
            my @ids = @{$func{$_}};
            my @fid_gid = map  { [ $_, FIG::genome_of($_) || '' ] } @ids;

            #  Remove non-fig genomes
            my @no_gid  = grep { ! $_->[1] } @fid_gid;
            if ( @no_gid )
            {
                foreach ( @no_gid ) { $fid_grp{ $_ } = [] }
                @fid_gid = grep { $_->[1] } @fid_gid;
                next unless @fid_gid;
            }

            #  Cases of one genome are trivial
            if ( @fid_gid == 1 )
            {
                my ( $fid, $gid ) = @{ $fid_gid[0] };
                $fid_grp{ $fid } = [];
                $keep_gid{ $gid } ||= 1;
                next;
            }

            #  Every group remaining has more than one fig genome.
            #  We need to expand %keep_gid until it includes at least
            #  one member of each group.

            push @group, \@fid_gid;
            if ( ! grep { $keep_gid{$_->[1]} } @fid_gid )
            {
                push @unres, [ map { $_->[1] } @fid_gid ];
            }
        }
    }

    #  Complete a list of gids that will cover all of the sim groups
    if ( @unres )
    {
        #  Prioritize gids by number of groups they are in

        my %gid_cnt;
        foreach my $grp ( @unres )
        {
            foreach my $gid ( @$grp ) { $gid_cnt{ $gid }++ }
        }

        #  Prioritize groups by their size

        foreach my $grp ( sort { @{ $b } <=> @{ $a } } @unres )
        {
            #  Make sure the group still is unresolved
            next if ( grep { $keep_gid{ $_ } } @$grp );
            #  Find the highest priority gid in the group
            my ( $gid ) = sort { $gid_cnt{ $b } <=> $gid_cnt{ $a } } @$grp;
            #  Flag the gid
            $keep_gid{ $gid } = 1;
        }
    }

    if ( @group )
    {
        #  We have a set of gids that cover all groups
        #  It is now necessary to find define the actual fid groups

        foreach my $grp ( @group )
        {
            my ( $rep, @reps ) = sort { $keep_gid{ $b->[1] } <=> $keep_gid{ $a->[1] } }
                                 grep { $keep_gid{ $_->[1] } }
                                 @$grp;
            $rep or print STDERR "Bummer. SimsTable::merge_identical_sims logic error.\n"
                    and next;

            my @extra = map  { $_->[0] }
                        grep { ! $keep_gid{ $_->[1] } }
                        @$grp;

            $fid_grp{ $rep->[0] } = \@extra;

            foreach ( @reps ) { $fid_grp{ $_->[0] } = [] }
        }
    }

    #  Return the filtered sims
    grep { $fid_grp{ $_->id2 } } @$sims;
}


#-------------------------------------------------------------------------------
#  @cols = process_col_request( $cgi, $col_request, $parameters )
#-------------------------------------------------------------------------------

sub process_col_request
{
    my ( $cgi, $col_request, $parameters ) = @_;
    return () unless ( $cgi && $col_request && ref $col_request eq 'ARRAY' && @$col_request );
    $parameters ||= {};

    #  Figure out the columns

    my $rgn_clr_help  = '<SPAN Style="font-size:smaller;">(<A href="Html/similarity_region_colors.html" target="SEED_or_SPROUT_help">colors</A>)</SPAN>';
    my $func_clr_help = '<SPAN Style="font-size:smaller;">(<A href="Html/function_colors.html" target="SEED_or_SPROUT_help">colors</A>)</SPAN>';
    my $ev_code_help  = &evidence_codes_link( $cgi );

    #  Recognized keywords and default titles

    my %label = ( q_id         =>   'Query ID',
                  q_def        =>   'Query Function',
                  q_function   =>   'Query Function',
                  q_genome     =>   'Query Genome',
                  q_region     =>   "Query<BR />Region<BR />$rgn_clr_help",
                  q_subsys     =>   'Query<BR />Subsys',
                  q_evidence   =>   "Query<BR />$ev_code_help",
                  q_aliases    =>   'Query aliases',

                  s_id         =>   'Match ID',
                  s_rep        =>   'Other<BR />IDs',
                  s_def        =>   'Match Function',
                  s_function   =>   'Match Function',
                  s_genome     =>   'Match Genome',
                  s_region     =>   "Match<BR />Region<BR />$rgn_clr_help",
                  s_subsys     =>   'Match<BR />Subsys',
                  s_evidence   =>   "Match<BR />$ev_code_help",
                  s_aliases    =>   'Match aliases',

                  e_val        =>   'E-val',
                  p_val        =>   'E-val',
                  identity     =>   '% iden',
                  score        =>   'Bit<BR />score',
                  bpp          =>   'Bits<BR />per<BR />pos',
                  bits_per_pos =>   'Bits<BR />per<BR />pos',
                  nbs          =>   'Norm<BR />bit<BR />score',
                  nbsc         =>   'Norm<BR />bit<BR />score',

                  checked      =>   'Select',
                  checked_t    =>   '<SPAN Style="white-space: nowrap;">Assign to<BR /><SPAN Style="font-size: smaller;">or</SPAN><BR />Translate from</SPAN>',
                  checked_a    =>   '<SPAN Style="white-space: nowrap;">Assign to<BR /><SPAN Style="font-size: smaller;">or</SPAN><BR />Select</SPAN>',
                  checked_s    =>   'Select',

                  from         =>   'Assign<BR />from',
               );

    if ( $parameters->{ fid_group } && ! grep { m/^s_rep/i } @$col_request )
    {
        @$col_request = map { m/^s_id/i ? qw( s_id s_rep ) : ( $_ ) } @$col_request;
    }

    my @columns;
    foreach my $req ( @$col_request )
    {
        my ( $value, $label ) = &interpret_column_request( $req, \%label, $parameters );
        push @columns, [ $value, $label ] if $value;
    }

    @columns;
}


#-------------------------------------------------------------------------------
#  @cols = evidence_codes_link( $cgi )
#-------------------------------------------------------------------------------

=pod

=item * B<evidence_codes_link> ()

Returns an HTML link to the evidence codes explanation page

=back

=cut

sub evidence_codes_link
{
    return '<A href="Html/evidence_codes.html" target="SEED_or_SPROUT_help">Ev<BR />code</A>';
}


#-------------------------------------------------------------------------------
#  ( $value, $label ) = interpret_column_request( $request, $label, $parameters )
#-------------------------------------------------------------------------------

sub interpret_column_request
{
    my ( $request, $label, $parameters ) = @_;
    return () unless $request && $label;
    $parameters ||= {};

    if ( ! ref( $request ) )
    {
        return &col_key_and_label( $request, $label, $parameters );
    }

    if ( ref( $request ) ne 'ARRAY' || ! @$request || ! $request->[0] )
    {
        return ();
    }

    my $value;
    ( $value, $label ) = @$request;
    
    if ( ! ref( $value ) )
    {
        my ( $v, $l ) = &col_key_and_label( $value, $label, $parameters );
        return $v ? ( $v, $label || $l ) : ();
    }

    if ( ref( $value ) eq 'HASH' || ref( $value ) eq 'CODE' )
    {
        return ( $value, $label );
    }

    return ();
}


#-------------------------------------------------------------------------------
#  ( $key, $label ) = col_key_and_label( $value, $label, $parameters )
#-------------------------------------------------------------------------------

sub col_key_and_label
{
    my ( $value, $label, $parameters ) = @_;
    return () unless $value && $label;
    $parameters ||= {};

    my $user  = $parameters->{ user }      || '';
    my $trans = $parameters->{ translate } || '';

    my @parts = map { /^checked/ ? ( $trans ? 'checked_t' : $user  ? 'checked_a' : 'checked_s' ) : $_ }
                split /\//, $value;
    my @lbls  = grep { defined $_ } map { $label->{ $_ } } @parts;

    @parts == @lbls ? ( join( '/', @parts ), join( '<HR Width=80% />', @lbls ) ) : ();
}


#-------------------------------------------------------------------------------
#
#  Column data are hashes indexed by sim, and values that are pairs composed
#
#      $column_datum->{ $sim } = [ $cell_html, $row_span ]
#
#  A row span of 0 will be omitted from the table row; it is filled from above.
#
#-------------------------------------------------------------------------------
sub produce_column_data
{
    my ( $fig, $cgi, $request, $sims, $parameters ) = @_;
    $parameters ||= {};

    my $user = $parameters->{ user } || '';

    #  A user-supplied hash needs to have row span data added:

    if ( ref( $request ) eq 'HASH' )
    {
        my %result = map { $_ => [ TableCell->TD( defined_or_nbsp( $request->{$_} ) ), 1 ] }
                     @$sims;
    }

    #  A user-supplied function needs to be evaluated, and a row span added:

    if ( ref( $request ) eq 'CODE' )
    {
        my %result = map { my $val = &$request( $fig, $cgi, $_, $parameters );
                           ( $_ => [ TableCell->TD( defined_or_nbsp( $val ) ), 1 ] );
                         }
                     @$sims;
        return \%result;
    }

    #  No other reference makes sense:

    return {}  if ( ref $request );   #  Very bad

    #  Scalar values are taken to be keywords that define the values:

    my @results = map { &process_column_keyword( $fig, $cgi, $_, $sims, $parameters ) }
                  split /\//, $request;

    #  One keyword is easy, just pass back the hash:

    return $results[0]  if ( @results == 1 );

    #  More than one keyword requires joining the values and setting the
    #  row span to the smallest value of those being merged (most commonly,
    #  values that are likely to get put in a single cell will be unique to
    #  every row, but ....

    my %results;
    my $n_skip = 0;
    foreach my $sim ( @$sims )
    {
        if ( $n_skip-- > 0 ) { $results{$sim} = [ '', 0 ]; next }

        my @sim_results = map { $_->{ $sim } } @results;

        my $text = join( $cgi->br, map { &html_esc( $_->[0]->text() ) } @sim_results );
        my $cell = TableCell->TD( $text, 1 );

        $cell->add_style( 'white-space' => 'nowrap', 'text-align' => 'center' );

        my ( $clr ) = grep { $_ }
                      map { $_->[0]->style( 'background->color' ) }
                      @sim_results;
        $cell->add_style( 'background->color' => $clr ) if $clr;

        my ( $span ) = sort { $a <=> $b }
                       grep { $_ }
                       map  { $_->[1] }
                       @sim_results;

        $results{$sim} = [ $cell, $span ];

        $n_skip = $span - 1;
    }

    return \%results;
}


#-------------------------------------------------------------------------------
#
#    \%data_keyed_by_sim = process_column_keyword( $fig, $cgi, $item, $sims, $parameters )
#
#     $datum = [ $cell_object, $row_span ]
#
#     $item is a keyword, or composite
#
#       q_id
#       q_def
#       q_genome
#    X  q_region
#       q_subsys
#       q_evidence
#       q_aliases
#
#    X  s_id
#       s_rep
#    X  s_def
#    X  s_genome
#    X  s_region
#    X  s_subsys
#    X  s_evidence
#       s_aliases
#
#       e_val = p_val
#       identity
#       score
#       bpp = bits_per_pos = nbs
#
#    X  checked
#    X  from
#-------------------------------------------------------------------------------

sub process_column_keyword
{
    my ( $fig, $cgi, $item, $sims, $parameters ) = @_;
    return {}  unless $fig && $cgi && $item && $sims;

    $parameters ||= {};
    my $user           = $parameters->{ user }          || '';
    my $same_qid_sid   = $parameters->{ same_qid_sid }  || {};
    my $same_qid_sgen  = $parameters->{ same_qid_sgen } || $same_qid_sid;
    my $func_by_id     = $parameters->{ func_by_id };
    my $genome_by_id   = $parameters->{ genome_by_id };
    my $func_cell_data = $parameters->{ func_cell_data };
    my $fid_group      = $parameters->{ fid_group }     || {};

    my %data;

    if    ( $item eq 'q_id' )
    {
        %data = map { $_ => [ &id_cell( $fig, $cgi, $_->id1 ),
                              &row_span( $same_qid_sid, $_ )
                            ]
                    }
                @$sims;
    }

    elsif ( $item eq 'q_def' || $item eq 'q_function' )
    {
        %data = map { $_ => [ &def_cell( $_->id1, $func_by_id, $func_cell_data ),
                              &row_span( $same_qid_sid, $_ )
                            ]
                    }
                @$sims;
    }

    elsif ( $item eq 'q_genome' )
    {
        %data = map { $_ => [ &genome_cell( $fig, $_->id1, $genome_by_id ),
                              &row_span( $same_qid_sid, $_ )
                            ]
                    }
                @$sims;
    }

    elsif ( $item eq 'q_region' )
    {
        %data = map { $_ => [ &region_cell( $_->b1, $_->e1, $_->ln1 ), 1 ] }
                @$sims;
    }

    elsif ( $item eq 'q_subsys' )
    {
        %data = map { $_ => [ &subsystem_cell( $fig, $cgi, $_->id1 ),
                              &row_span( $same_qid_sid, $_ )
                            ]
                    }
                @$sims;
    }

    elsif ( $item eq 'q_evidence' )
    {
        %data = map { $_ => [ &evidence_code_cell( $fig, $cgi, $_->id1 ),
                              &row_span( $same_qid_sid, $_ )
                            ]
                    }
                @$sims;
    }

    elsif ( $item eq 'q_aliases' )
    {
        %data = map { $_ => [ &aliases_cell( $fig, $cgi, $_->id1 ),
                              &row_span( $same_qid_sid, $_ )
                            ]
                    }
                @$sims;
    }

    elsif ( $item eq 's_id' )
    {
        %data = map { $_ => [ &id_cell( $fig, $cgi, $_->id2 ),
                              &row_span( $same_qid_sid, $_ )
                            ]
                    }
                @$sims;
    }

    elsif ( $item eq 's_rep' )
    {
        %data = map { $_ => [ &rep_cell( $fig, $cgi, $fid_group->{$_->id2}, $genome_by_id ),
                              &row_span( $same_qid_sid, $_ )
                            ]
                    }
                @$sims;
    }

    elsif ( $item eq 's_def' || $item eq 's_function'  )
    {
        %data = map { $_ => [ &def_cell( $_->id2, $func_by_id, $func_cell_data ),
                              &row_span( $same_qid_sid, $_ )
                            ]
                    }
                @$sims;
    }

    elsif ( $item eq 's_genome' )
    {
        %data = map { $_ => [ &genome_cell( $fig, $cgi, $_->id2, $genome_by_id ),
                              &row_span( $same_qid_sgen, $_ )
                            ]
                    }
                @$sims;
    }

    elsif ( $item eq 's_region' )
    {
        %data = map { $_ => [ &region_cell( $_->b2, $_->e2, $_->ln2 ), 1 ] }
                @$sims;
    }

    elsif ( $item eq 's_subsys' )
    {
        %data = map { $_ => [ &subsystem_cell( $fig, $cgi, $_->id2 ),
                              &row_span( $same_qid_sid, $_ )
                            ]
                    }
                @$sims;
    }

    elsif ( $item eq 's_evidence' )
    {
        %data = map { $_ => [ &evidence_code_cell( $fig, $cgi, $_->id2 ),
                              &row_span( $same_qid_sid, $_ )
                            ]
                    }
                @$sims;
    }

    elsif ( $item eq 's_aliases' )
    {
        %data = map { $_ => [ &aliases_cell( $fig, $cgi, $_->id2 ),
                              &row_span( $same_qid_sid, $_ )
                            ]
                    }
                @$sims;
    }

    elsif ( $item eq 'e_val' || $item eq 'p_val' )
    {
        my $p;
        %data = map { $_ => [ &e_value_cell( $_->psc ), 1 ] }
                @$sims;
    }

    elsif ( $item eq 'identity' )
    {
        %data = map { $_ => [ &identity_cell( $_->iden ), 1 ] }
                @$sims;
    }

    elsif ( $item eq 'score' )
    {
        %data = map { $_ => [ &score_cell( $_->bsc ), 1 ] }
                @$sims;
    }

    elsif ( $item eq 'bpp' || $item eq 'bits_per_pos' || $item =~ /^nbs/ )
    {
        %data = map { $_ => [ &nbsc_cell( $_->nbsc ), 1 ] }
                @$sims;
    }

    elsif ( $item =~ /^checked/ )
    {
        %data = map { $_ => [ checkbox_cell( $fig, $cgi, $_->id2, $fig->translatable( $_->id2 ), $genome_by_id ),
                              &row_span( $same_qid_sid, $_ )
                            ]
                    }
                @$sims;
    }

    elsif ( $item =~ /^from/ )
    {
        my $from = $parameters->{ from_buttons };  #  A list of the buttons
        if ( $from && ref( $from ) eq 'ARRAY' && $func_by_id && ref( $func_by_id ) eq 'HASH' )
        {
            my $n = 0;
            %data = map { $_ => [ &from_cell( $from->[ $n++ ], $func_by_id->{$_->id2} ),
                                  &row_span( $same_qid_sid, $_ )
                                ]
                        }
                    @$sims;
        }
    }

    # else { }

    \%data;
}


sub row_span
{
    my ( $spans, $sim ) = @_;
    my $span = $spans && $sim ? $spans->{ $sim } : undef;
    defined $span ? $span : 1;
}


#-------------------------------------------------------------------------------
#  An id: linked to site; colored by function lock status
#-------------------------------------------------------------------------------

sub id_cell
{
    my ( $fig, $cgi, $id ) = @_;
    return TableCell->nbsp unless $fig && $cgi && $id;

    my $link = &HTML::set_prot_links( $cgi, $id );
    chomp $link;
    my $cell = TableCell->TD( $link, 1 );
    $cell->add_style( 'background-color' => $locked_color ) if $fig->is_locked_fid($id);
    $cell;
}


#-------------------------------------------------------------------------------
#  A list of subsumed ids, with menu of links
#-------------------------------------------------------------------------------

sub rep_cell
{
    my ( $fig, $cgi, $ids, $genome_by_id ) = @_;
    return TableCell->nbsp unless $fig && $cgi && $ids && @$ids;
    $genome_by_id ||= {};

    my @data = sort { lc $a->[1] cmp lc $b->[1]  # alphabetical
                   ||    $a->[2] <=>    $b->[2]  # taxid
                   ||    $a->[3] <=>    $b->[3]  # genome version
                   ||    $a->[4] <=>    $b->[4]  # peg number
                   ||    $a->[0] cmp    $b->[0]  # id string
                    }
               map  { $_->[0] =~ /^fig\|(\d+)\.(\d+)\.[^.]+\.(\d+)$/ ? [@$_,$1,$2,$3] : [@$_,0,0,0] }
               map  { $genome_by_id->{$_} ? [$_,$genome_by_id->{$_}->[0]] : [$_,''] }
               @$ids;

    my $n = @data;
    my $names = join '<BR />', map { $_->[1] ? html_esc( $_->[1] ) : $_->[0] }
                               @data;
    my $links = join '<BR />', 'Identical proteins:',
                               map { &HTML::set_prot_links( $cgi, $_ ) }
                               map { $_->[1] ? "$_->[0] &mdash; " . html_esc($_->[1]) : $_->[0] }
                               @data;

    # my $tip = FIGjs::mouseover( $title, $text, $menu, $parent, $hc, $bc );
    my $tip = FIGjs::mouseover( 'Identical Proteins', $names, $links, '', '#888800', '#FFFF00' );

    my $cross = 0x271A;
    my $cell = TableCell->TD( "<SPAN $tip>&#$cross ($n)</SPAN>", 1 );
    $cell->add_style( 'text-align' => 'center' );
    $cell;
}


#-------------------------------------------------------------------------------
#  A function definition: colored by function
#-------------------------------------------------------------------------------

sub def_cell
{
    my ( $id, $func_by_id, $func_cell_data ) = @_;
    return TableCell->nbsp unless $id && $func_by_id && $func_cell_data;

    my $func = $func_by_id->{ $id };
    return TableCell->nbsp unless defined( $func );

    my $func_and_clr = $func_cell_data->{ $func };
    return TableCell->nbsp unless $func_and_clr && defined $func_and_clr->[0];

    my $clr;
    ( $func, $clr ) = @$func_and_clr;
    my $cell = TableCell->TD( $func, 1 );
    $cell->add_style( 'background-color' => $clr ) if $clr;
    $cell;
}


#-------------------------------------------------------------------------------
#  Aliases: linked to sites
#-------------------------------------------------------------------------------

sub aliases_cell
{
    my ( $fig, $cgi, $id ) = @_;
    return TableCell->nbsp unless $fig && $cgi && $id;

    my $aliases = &html_esc( join( ", ", $fig->feature_aliases( $id ) ) );
    TableCell->TD( HTML::set_prot_links( $cgi, $aliases ), 1 );
}


#-------------------------------------------------------------------------------
#  A genome: colored by domain
#-------------------------------------------------------------------------------

sub genome_cell
{
    my ( $fig, $cgi, $id, $genome_by_id ) = @_;
    return TableCell->nbsp unless $fig && $cgi && $id;

    $genome_by_id ||= {};

    my ( $gs, $clr );
    if ( $genome_by_id->{ $id } )
    {
        ( $gs, $clr ) = @{ $genome_by_id->{ $id } };
    }
    else
    {
        ( $gs, $clr ) = $fig->org_and_color_of( $id );
        $genome_by_id->{ $id } = [ $gs, $clr ];
    }
    return TableCell->nbsp unless $gs;

    my $cell = TableCell->TD( $gs );
    $cell->add_style( 'background-color' => $clr ) if $clr;
    $cell;
}


#-------------------------------------------------------------------------------
#  Subsystems: with tooltip giving details
#-------------------------------------------------------------------------------

sub subsystem_cell
{
    my ( $fig, $cgi, $fid ) = @_;
    return TableCell->nbsp unless $fig && $cgi && $fid;

    my @in_sub = $fig->peg_to_subsystems( $fid );
    return TableCell->nbsp unless @in_sub;

    # RAE: add a javascript popup with all the subsystems
    my $ss_list = join( $cgi->br, map { s/\_/ /g; $_ } sort { lc $a cmp lc $b } @in_sub );
    my $cell = TableCell->TD( &text_with_tool_tip( $cgi, 'subsystems', 'Subsystems', $ss_list, scalar @in_sub ), 1);
    $cell->add_style( 'text-align' => 'center' );
    $cell;
}


#-------------------------------------------------------------------------------
#  Evidence codes: with tooltip giving details
#-------------------------------------------------------------------------------

sub evidence_code_cell
{
    my ( $fig, $cgi, $fid ) = @_;
    return TableCell->nbsp unless $fig && $fid;

    my @ev_codes = &evidence_codes( $fig, $fid );
    return TableCell->nbsp unless @ev_codes && $ev_codes[0];
    my %dup;
    my $ev_code_help = join( $cgi->br, grep { ! $dup{$_}++ }
                                       map  { &HTML::evidence_codes_explain($_) } @ev_codes );

    my $cell = TableCell->TD( &text_with_tool_tip( $cgi, 'evidence_codes', 'Evidence Codes', $ev_code_help, join( $cgi->br, @ev_codes ) ), 1 );
    $cell->add_style( 'text-align' => 'center' );
    $cell;
}


sub text_with_tool_tip
{
    my ( $cgi, $id, $title, $tip, $link_text ) = @_;
    $cgi->a( { id          => $id,
               onMouseover => "javascript:if(!this.tooltip) this.tooltip=new Popup_Tooltip(this, '$title', '$tip', ''); this.tooltip.addHandler(); return false;"
             },
             $link_text
           )
}


#-------------------------------------------------------------------------------
#  E-value: fommatted data
#-------------------------------------------------------------------------------

sub e_value_cell
{
    my ( $e_value ) = @_;
    return TableCell->nbsp unless defined $e_value && length $e_value;

    $e_value =~ s/e-0(\d\d)/e-$1/i;
    $e_value = '0.0' if $e_value == 0;
    TableCell->TD( $e_value, 1 );
}


#-------------------------------------------------------------------------------
#  Identity: fommatted data
#-------------------------------------------------------------------------------

sub identity_cell
{
    my ( $identity ) = @_;
    return TableCell->nbsp unless $identity;


    TableCell->TD( sprintf( '%.1f%%', $identity ), 1 );
}


#-------------------------------------------------------------------------------
#  Score: fommatted data
#-------------------------------------------------------------------------------

sub score_cell
{
    my ( $score ) = @_;
    return TableCell->nbsp unless $score;

    TableCell->TD( $score, 1 );
}


#-------------------------------------------------------------------------------
#  Normalized bit score: fommatted data
#-------------------------------------------------------------------------------

sub nbsc_cell
{
    my ( $nbsc ) = @_;
    return TableCell->nbsp unless $nbsc;

    TableCell->TD( sprintf( '%.3f', $nbsc ), 1 );
}



#-------------------------------------------------------------------------------
#  A selection checkbox: dependend upon translatable(); centered and colored by genome domain
#-------------------------------------------------------------------------------

sub checkbox_cell
{
    my ( $fig, $cgi, $id, $show, $genome_by_id ) = @_;
    return TableCell->nbsp unless $cgi && $id;

    $genome_by_id ||= {};

    my $cell = TableCell->TD( $show ? $cgi->checkbox( -name => 'checked', -value => $id, -override => 1, -label => '' ) : '&nbsp;', 1 );
    my $clr = $genome_by_id->{ $id } ? $genome_by_id->{ $id }->[1] : '';
    $cell->add_style( 'text-align' => 'center' );
    $cell->add_style( 'background-color' => $clr ) if $clr;
    $cell;
}


#-------------------------------------------------------------------------------
#  A from radiobutton: dependent upon a non-blank function; centered
#-------------------------------------------------------------------------------

sub from_cell
{
    my ( $from, $func ) = @_;
    return TableCell->nbsp unless $from && $func;

    my $cell = TableCell->TD( $from, 1 );
    $cell->add_style( 'text-align' => 'center' );
    $cell;
}


#-------------------------------------------------------------------------------
#  Match regions: fommatted data, colored by region, and nowrap
#-------------------------------------------------------------------------------

sub region_cell
{
    my ( $b, $e, $len ) = @_;
    return TableCell->nbsp unless $b && $e && $len;

    my $d = abs( $e - $b ) + 1;
    my $cell = TableCell->TD( "$b-$e<BR />(<B>$d/$len</B>)", 1 );
    my $clr = &region_color( $b, $e, $len );
    $cell->add_style( 'text-align'       => 'center',
                      'background-color' => $clr,
                      'white-space'      => 'nowrap'
                    );
    $cell;
}


sub region_color
{
    my ( $b, $e, $n ) = @_;
    my ( $l, $r ) = ( $e > $b ) ? ( $b, $e ) : ( $e, $b );
    my $hue = 5/6 * 0.5*($l+$r)/$n - 1/12;
    my $cov = ( $r - $l + 1 ) / $n;
    my $sat = 1 - 10 * $cov / 9;
    my $br  = 1;
    &rgb2html( &hsb2rgb( $hue, $sat, $br ) );
}


sub hsb2rgb
{
    my ( $h, $s, $br ) = @_;
    $h = 6 * ($h - floor($h));
    if ( $s  > 1 ) { $s  = 1 } elsif ( $s  < 0 ) { $s  = 0 }
    if ( $br > 1 ) { $br = 1 } elsif ( $br < 0 ) { $br = 0 }
    my ( $r, $g, $b ) = ( $h <= 3 ) ? ( ( $h <= 1 ) ? ( 1,      $h,     0      )
                                      : ( $h <= 2 ) ? ( 2 - $h, 1,      0      )
                                      :               ( 0,      1,      $h - 2 )
                                      )
                                    : ( ( $h <= 4 ) ? ( 0,      4 - $h, 1      )
                                      : ( $h <= 5 ) ? ( $h - 4, 0,      1      )
                                      :               ( 1,      0,      6 - $h )
                                      );
    ( ( $r * $s + 1 - $s ) * $br,
      ( $g * $s + 1 - $s ) * $br,
      ( $b * $s + 1 - $s ) * $br
    )
}


sub rgb2html
{
    my ( $r, $g, $b ) = @_;
    if ( $r > 1 ) { $r = 1 } elsif ( $r < 0 ) { $r = 0 }
    if ( $g > 1 ) { $g = 1 } elsif ( $g < 0 ) { $g = 0 }
    if ( $b > 1 ) { $b = 1 } elsif ( $b < 0 ) { $b = 0 }
    sprintf("#%02x%02x%02x", int(255.999*$r), int(255.999*$g), int(255.999*$b) )
}


sub floor
{
    my $x = $_[0];
    defined( $x ) || return undef;
    ( ( $x >= 0 ) || ( int($x) == $x ) ) ? int( $x ) : -1 - int( - $x )
}


sub defined_or_nbsp { defined $_[0] ? $_[0] : '&nbsp;' }


sub html_esc { local $_ = $_[0]; s/\&/&amp;/g; s/\>/&gt;/g; s/\</&lt;/g; $_ }


sub trans_function_of
{
    my ( $fig, $cgi, $peg ) = @_;

    if (wantarray())
    {
        my @funcs = $fig->function_of( $peg );
        if ($cgi->param('translate'))
        {
            @funcs = map { $_->[1] = $fig->translate_function( $_->[1]) ; $_ } @funcs;
        }
        return @funcs;

    }
    else
    {
        my $func = $fig->function_of( $peg, $cgi->param( 'user' ) );
        if ($cgi->param('translate'))
        {
            $func = $fig->translate_function( $func );
        }
        return $func;
    }
}


sub evidence_codes
{
    my( $fig, $peg ) = @_;

    return () unless $peg =~ /^fig\|\d+\.\d+\.peg\.\d+$/;

    #  Attributes are [ id, type, value, url ]
    my @pretty_codes = ();
    foreach my $code ( $fig->get_attributes( $peg, 'evidence_code' ) )
    {
	my $pretty_code = $code->[2];
	$pretty_code =~ s/;.*$//;
	push @pretty_codes, $pretty_code;
    }

    @pretty_codes;
}


1;
