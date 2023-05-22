# -*- perl -*-
#
# Copyright (c) 2003-2008 University of Chicago and Fellowship
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

# comment for debugging - there are latent bugs in here that strict exposes!
use strict;
use HTML;
use FIG_CGI;
use TemplateObject;
use FIGgjo;        # colorize_roles, colorize_functions
use gjoalignment;  # align_with_clustal, align_with_muscle
use gjoseqlib;     # read_fasta, print_alignment_as_fasta
use gjoalign2html; # repad_alignment, color_alignment_by_consensus
use clustaltree;   # tree_with_clustal
use gjonewicklib;
use Data::Dumper;

use Carp;

my($fig, $cgi, $user) = FIG_CGI::init(debug_save        => 0,
                                      debug_load        => 0,
                                      print_params      => 0);

my $to = TemplateObject->new($cgi, php => 'Align');

my $peg_id    = $cgi->param('fid');
my $maxN      = $cgi->param('maxN');
my $maxP      = $cgi->param('maxP');
my @checked   = $cgi->multi_param('checked');
my @checked_figfam = $cgi->multi_param('checked_figfam');
my @from      = $cgi->multi_param('from');
my $function  = $cgi->param('function');
$function=$fig->clean_spaces($function);
my($timestamp,$who,$annotation);
#print STDERR "\n\n$0: ", (scalar localtime(time())), "\n";
#print STDERR "\@from =    ", Dumper(\@from);
#print STDERR "\@checked = ", Dumper(\@checked);
if (is_sprout($cgi) || ! defined($user)) { $user = "" }

# The forms will be assembled here.
my $formData = "";
# The alignment will be assembled here.
my $alignData = "";
# The tree will be assembled here.
my $treeData = "";
# Useful debugging stuff will be put here.
my $paramData = "";
# Display the features selected.
if (@checked == 0) {
    $paramData .= "<p>No features selected.</p>\n";
} else {
    $paramData .= "<p>Features selected: " . join(", ", @checked) . ".</p>\n";
}

my $sproutFlag = (is_sprout($cgi) ? "&SPROUT=1" : "");

#==============================================================================
#  align
#
#  Nearly total rewrite by GJO -- 2007-04-09
#  Modify to periodically update page -- GJO, 2009-06-24
#==============================================================================

if ( ( $cgi->param('align') && ( @checked >= 2 || $cgi->param('cached') ) )
    || $cgi->param('update')
   )
{
    print $cgi->header;

    my $agent  = $ENV{ HTTP_USER_AGENT } || '';
    my $height = $agent =~ /Safari/i  ? '110%'
               : $agent =~ /Firefox/i ? '100%'
               :                        '100%';
    my $lsize  = $agent =~ /Safari/i  ? '160%'
               : $agent =~ /Firefox/i ? '130%'
               :                        '140%';

    $formData .= <<End_of_Head;
<HTML>
<HEAD>
<TITLE>The SEED: Alignment and Tree of Proteins</TITLE>

<STYLE Type="text/css">
  /* Support for HTML printer graphics tree */
  DIV.tree {
    border-spacing: 0px;
    font-size:     100%;
    line-height:    $height;
    white-space: nowrap;
  }
  DIV.tree A {
    text-decoration: none;
  }
  DIV.tree PRE {
    padding:    0px;
    margin:     0px;
    font-size: $lsize;
    display: inline;
  }
  DIV.tree INPUT {
    padding: 0px;
    margin:  0px;
    height: 10px;    /* ignored by Firefox */
    width:  10px;    /* ignored by Firefox */
  }
  DIV.tree SPAN.w {  /* used for tree white space */
    color: white;
  }
</STYLE>

</HEAD>
<BODY>
End_of_Head

    #----------------------------------------------------------------------
    #  Make ids unique and get a sequence.
    #  But don't need sequences if cached.
    #----------------------------------------------------------------------

    my @seqs;
    my $cached = $cgi->param('cached') || '';
    my $newcache = $cached
               || ("fid_checked_data_" . $$ . "_" . sprintf( '%09d', int(1e9*rand())));

    if ( ! $cached )
    {
        my %seen;
        @seqs = grep { $_->[2] }
                map  { [ $_, '', $fig->get_translation( $_ ) ] }
                grep { ! $seen{ $_ }++ }
                @checked;
        @checked = map { $_->[0] } @seqs;
        write_cached_ids( $newcache, \@checked );
    }

    if ( $cached && ! @checked )
    {
        @checked = read_cached_ids( $cached );
    }

    #----------------------------------------------------------------------
    #  Find the current functions:
    #----------------------------------------------------------------------

    my ( $fid, $func );
    my %fid_func = ();

    foreach $fid ( @checked )
    {
        $func = $fig->function_of( $fid, $user ) || "";
        $func =~ s/ +;/;/g;              # An ideosyncracy of some assignments
        $fid_func{ $fid } = $func;
    }

    #----------------------------------------------------------------------
    #  Build a role-to-color translation table based on frequency of
    #  function. Normally white is reserved for the current function, but
    #  there is none here. Assign colors until we run out, then go gray.
    #  Undefined function is not in %func_color, and so is not in
    #  %formatted_func
    #----------------------------------------------------------------------

    my %formatted_func = &FIGgjo::colorize_roles( \%fid_func );

    #----------------------------------------------------------------------
    #  Get the organism names:
    #----------------------------------------------------------------------

    my %orgs = map { $_ => $fig->org_of( $_ ) || '' } @checked;

    my $sprout = $cgi->param('SPROUT') ? 1 : "";
    my $target = "window$$";

    $alignData .= "<h2>Alignment of Selected Proteins</h2>\n";

    #----------------------------------------------------------------------
    #  Alignment:
    #----------------------------------------------------------------------
    #  Make or retreive the alignment:

    my @align;
    if ( $cached )
    {
        @align = read_cached_align( $cached );
    }
    else
    {
        # @align = gjoalignment::align_with_clustal( @seqs );
        @align = @{ scalar gjoalignment::align_with_muscle( \@seqs ) };
        write_cached_align( $newcache, \@align ) if @align;
    }

    #----------------------------------------------------------------------
    #  Tree:
    #----------------------------------------------------------------------
    #  Make or retreive the tree:

    my $tree;
    if ( $cached )
    {
        $tree = read_cached_tree( $cached );
        $treeData .= "<BR />Failed to retreive previous tree<BR />" if ! $tree;
    }
    else
    {
        $tree = clustaltree::tree_with_clustal( \@align );
        if ( $tree )
        {
            #  Reroot, reorder and cache the tree:
            my $tree2 = gjonewicklib::reroot_newick_to_midpoint_w( $tree );
            $tree = gjonewicklib::aesthetic_newick_tree( $tree2 );
            write_cached_tree( $newcache, $tree );
        }
        else
        {
            $treeData .= "<BR />Failed to make tree<BR />";
        }
    }

    if ( $tree )
    {
        #  Reorder alignment by tree:
        my %align = map { $_->[0] => $_ } @align;
        @align = map { $align{ $_ } } gjonewicklib::newick_tip_list( $tree );

	$treeData .= "<h2>Neighbor-joining Tree of Selected Proteins</h2>\n";
    }

    #----------------------------------------------------------------------
    #  Render alignment:
    #----------------------------------------------------------------------

    my $color_aln_by = $cgi->param( 'color_aln_by' ) || 'residue';
    my $align_format = $cgi->param( 'align_format' );
    my $tree_format  = $cgi->param( 'tree_format' )  || 'default';
    my $hide_aliases = $cgi->param( 'hide_aliases' ) || '';

    if ( @align && ( $align_format eq "fasta" ) )
    {
        my $id;
        my %def = map { $id = $_->[0];
                        $id => join( ' ', $id,
                                          ( $fid_func{ $id } ? $fid_func{ $id } : () ),
                                          ( $orgs{ $id } ? "[$orgs{$id}]" : () )
                                   )
                      }
                  @align;
        my $tseq;
        $alignData .= join( "\n",
                            "<pre>",
                            ( map { ( ">$def{$_->[0]}", $_->[2] =~ m/(.{1,60})/g ) } @align ),
                           "</pre>\n"
                          );
    }
    elsif ( @align && ( $align_format eq "clustal" ) )
    {
        my $clustal_alignment = &to_clustal( \@align );
        $alignData .= "<pre>\n$clustal_alignment</pre>\n";
    }
    elsif ( @align )
    {
        my ( $align2, $legend );

        #  Color by residue type:

        if ( $color_aln_by eq 'residue' )
        {
            my %param1 = ( align => \@align, protein => 1 );
            $align2 = gjoalign2html::color_alignment_by_residue( \%param1 );
        }

        #  Color by consensus:

        elsif ( $color_aln_by ne 'none' )
        {
            my %param1 = ( align => \@align );
            ( $align2, $legend ) = gjoalign2html::color_alignment_by_consensus( \%param1 );
        }

        #  No colors:

        else
        {
            $align2 = gjoalign2html::repad_alignment( \@align );
        }

        #  Add organism names:

        foreach ( @$align2 ) { $_->[1] = $orgs{ $_->[0] } }

        #  Build a tool tip with organism names and functions:

        my %tips = map { $_ => [ $_, join( '<HR>', $orgs{ $_ }, $fid_func{ $_ } ) ] }
                   @checked;
        $tips{ 'Consen1' } = [ 'Consen1', 'Primary consensus residue' ];
        $tips{ 'Consen2' } = [ 'Consen2', 'Secondary consensus residue' ];

        my %param2 = ( align   => $align2,
                       ( $legend ? ( legend  => $legend ) : () ),
                       tooltip => \%tips
                     );

        $alignData .= join( "\n",
                           scalar gjoalign2html::alignment_2_html_table( \%param2 ),
                           $cgi->br,
                         );
    }

    if ( @align )
    {
	$alignData .= join( "\n",
                             $cgi->start_form( -method => 'post',
                                               -action => 'fid_checked.cgi',
                                               -name   => 'alignment'
                                             ),
                             $cgi->hidden( -name => 'fid',     -value => $peg_id ),
                             $cgi->hidden( -name => 'SPROUT',  -value => $sprout ),
                             $cgi->hidden( -name => 'user',    -value => $user ),
                             $cgi->hidden( -name => 'cached',  -value => $newcache ),
                             $cgi->hidden( -name => 'checked', -value => [@checked] ),

                             'Color alignment by: ',
                             $cgi->radio_group( -name     => 'color_aln_by',
                                                -override => 1,
                                                -values   => [ 'consensus', 'residue', 'none' ],
                                                -default  => $color_aln_by
                                              ),

                             $cgi->br,
                             'Alignment format: ',
                             $cgi->radio_group( -name     => 'align_format',
                                                -override => 1,
                                                -values   => [ 'default', 'fasta', 'clustal' ],
                                                -default  => $align_format || 'default'
                                              ),

                             $cgi->br,
                             'Tree format: ',
                             $cgi->radio_group( -name     => 'tree_format',
                                                -override => 1,
                                                -values   => [ 'default', 'newick', 'png' ],
                                                -default  => $tree_format || 'default'
                                              ),

                             $cgi->br,
                             $cgi->checkbox( -name     => 'hide_aliases',
                                             -label    => 'Hide aliases in tree',
                                             -override => 1,
                                             -checked  => $hide_aliases
                                           ),

                             $cgi->br,
                             $cgi->submit( 'update' ),
                             $cgi->br
                          );
        $alignData .= $cgi->end_form . "\n";
    }

    #----------------------------------------------------------------------
    #  Render tree:
    #------------------------------------------------------------------
    #  Newick tree
    #------------------------------------------------------------------
    if ( $tree && ( $tree_format eq "newick" ) )
    {
	$treeData .= "<pre>\n" . &gjonewicklib::formatNewickTree($tree) . "</pre>\n";
    }

    #------------------------------------------------------------------
    #  PNG tree
    #------------------------------------------------------------------
    elsif ( $tree && ( $tree_format eq "png" ) )
    {
        my $okay;
        eval { require gd_tree_0; $okay = 1 };
        my $fmt;
        if ( $okay && ( $fmt = ( gd_tree::gd_has_png() ? 'png'  :
                                 gd_tree::gd_has_jpg() ? 'jpeg' :
                                                         undef
                               ) ) )
        {
            #------------------------------------------------------------------
            #  Aliases
            #------------------------------------------------------------------
            my %alias;
            if ( ! $hide_aliases )
            {
                %alias = map  { $_->[0] => $_->[1] } grep { $_->[1] }
                         map  { [ $_, scalar $fig->feature_aliases( $_ ) ] }
                         @checked;
            }
        
            #------------------------------------------------------------------
            #  Formulate the desired labels:
            #------------------------------------------------------------------
            my %labels;
            foreach $fid ( @checked )
            {
                my   @label;
                push @label, $fid;
                push @label, "[$orgs{$fid}]"             if $orgs{ $fid };
                push @label, $fid_func{ $fid }           if $fid_func{ $fid };
                push @label, html_esc( $alias{ $fid } )  if $alias{ $fid };
        
                $labels{ $fid } = join( ' ', @label );
            }
        
            #------------------------------------------------------------------
            #  Relabel the tips, midpoint root, pretty it up and draw
            #  the tree as printer plot
            #
            #  Adjustable parameters on text_plot_newick:
            #
            #     @lines = text_plot_newick( $node, $width, $min_dx, $dy )
            #------------------------------------------------------------------
            $tree = gjonewicklib::newick_relabel_nodes( $tree, \%labels );
            my $options = { thickness =>  2,
                            dy        => 15,
                          };
            my $gd = gd_tree::gd_plot_newick( $tree, $options );

            my $name = sprintf( "fid_checked_%d_%08d.$fmt", $$, int(1e8*rand()) );
            my $file = "$FIG_Config::temp/$name";
            open    TREE, ">$file";
            binmode TREE;
            print   TREE $gd->$fmt;
            close   TREE;
            chmod   0644, $file;

            my $url = &FIG::temp_url() . "/$name";
            $treeData .= $cgi->br . "\n"
                      . "<img src='$url' border=0>\n"
                      .  $cgi->br . "\n";
        }
        else
        {
            $treeData .= "<h3>Failed to convert tree to PNG.  Sorry.</h3>\n"
                      .  "<h3>Please choose another format above.</h3>\n";
        }
    }

    #------------------------------------------------------------------
    #  Printer plot tree
    #------------------------------------------------------------------
    else
    {
        #------------------------------------------------------------------
        #  Aliases
        #------------------------------------------------------------------
        my %alias;
        if ( ! $hide_aliases )
        {
            %alias = map  { $_->[0] => $_->[1] }
                     grep { $_->[1] }
                     map  { [ $_, scalar $fig->feature_aliases( $_ ) ] }
                     @checked;
        }

        #------------------------------------------------------------------
        #  Build checkboxes and radio buttons for appropriate sequences:
        #------------------------------------------------------------------

        my %check;
        my @translatable = grep { $fig->translatable( $_ ) } @checked;
        %check = map { $_ => qq(<INPUT Type=checkbox Name=checked Value="$_">) }
                 @translatable;

        my %from;
        if ( $user )
        {
            %from = map { m/value=\"([^\"]+)\"/; $1 => $_ }
                    $cgi->radio_group( -name     => 'from',
                                       -nolabels => 1,
                                       -override => 1,
                                       -values   => [ @translatable ],
                                       -default  => $peg_id
                                    );
        }

        #------------------------------------------------------------------
        #  Formulate the desired labels and relabel the tree tips
        #------------------------------------------------------------------
        my %labels;
        foreach $fid ( @checked )
        {
            my   @label;
            push @label, &HTML::fid_link( $cgi, $fid ) . '&nbsp;';
            push @label, $check{ $fid }                       if $check{ $fid };
            push @label, $from{ $fid }                        if $from{ $fid };
            push @label, $formatted_func{ $fid_func{ $fid } } if $fid_func{ $fid };
            push @label, "[$orgs{$fid}]"                      if $orgs{ $fid };
            push @label, html_esc( $alias{ $fid } )           if $alias{ $fid };

            $labels{ $fid } = join( ' ', @label );
        }

        $tree = gjonewicklib::newick_relabel_nodes( $tree, \%labels );

        #------------------------------------------------------------------
        #  Form and JavaScript added by RAE, 2004-Jul-22, 2004-Aug-23.
        #  Modified by GDP to make it DWWM, 2004-Jul-23, 2004-Aug-04.
        #------------------------------------------------------------------

        $treeData .= join( "\n",
                           $cgi->start_form( -method => 'post',
                                             -target => $target,
                                             -action => 'fid_checked.cgi',
                                             -name   => 'fid_checked'
                                           ),
                           $cgi->hidden( -name => 'align_format', -value => $align_format ),
                           $cgi->hidden( -name => 'color_aln_by', -value => $color_aln_by ),
                           $cgi->hidden( -name => 'fid',          -value => $peg_id ),
                           $cgi->hidden( -name => 'hide_aliases', -value => $hide_aliases ),
                           $cgi->hidden( -name => 'SPROUT',       -value => $sprout ),
                           $cgi->hidden( -name => 'tree_format',  -value => $tree_format ),
                           $cgi->hidden( -name => 'user',         -value => $user ),
                           ""
                         );

        #------------------------------------------------------------------
        #  Draw the tree as printer plot.
        #  Adjustable parameters on text_plot_newick:
        #
        #     @lines = text_plot_newick( $node, \%options )
        #
        #  Depends on document style:
        #
        #  <STYLE Type="text/css">
        #    /* Support for HTML printer graphics tree */
        #    DIV.tree {
        #      border-spacing: 0px;
        #      font-size:     10pt;
        #      line-height:   14px;
        #      white-space: nowrap;
        #    }
        #    DIV.tree A {
        #      text-decoration: none;
        #    }
        #    DIV.tree PRE {
        #      padding:    0px;
        #      margin:     0px;
        #      font-size: 14pt;
        #      display: inline;
        #    }
        #    DIV.tree INPUT {
        #      padding: 0px;
        #      margin:  0px;
        #      height: 10px;    /* ignored by Firefox */
        #      width:  10px;    /* ignored by Firefox */
        #    }
        #    DIV.tree SPAN.w {  /* used for tree white space */
        #      color: white;
        #    }
        #  </STYLE>
        #
        #------------------------------------------------------------------

        my $plot_options = { chars  => 'html',     # html-encoded unicode box set
                             format => 'tree_lbl', # line = [ $graphic, $label ]
                             dy     =>  1,
                             min_dx =>  1,
                             width  => 64
                           };
        $treeData .= join( "\n",
                           '',
                           '<DIV Class="tree" >',
                           ( map { my ( $line, $lbl ) = @$_;
                                   #  Fix white space for even spacing:
                                   $line =~ s/((&nbsp;)+)/<SPAN Class=w>$1<\/SPAN>/g;
                                   $line =~ s/&nbsp;/&#9474;/g;
                                   #  Output line, with or without label:
                                   $lbl ? "<PRE>$line</PRE> $lbl<BR />"
                                        : "<PRE>$line</PRE><BR />"
                                 }
                             text_plot_newick( $tree, $plot_options )
                           ),
                           '</DIV>',
                           '', ''
                         );

        #------------------------------------------------------------------
        # RAE Add the check all/uncheck all boxes.
        #------------------------------------------------------------------

        $treeData .= join ("\n", $cgi->br, &HTML::java_buttons("fid_checked", "checked"), $cgi->br, "");

        $treeData .= join("\n",
             "For selected (checked) sequences: "
             , $cgi->submit('align'),
             , $cgi->submit('view annotations')
             , $cgi->submit('show regions')
             , $cgi->br
             , ""
             );

        if ( $user && ! $sprout )
        {
            $treeData .= $cgi->submit('assign/annotate') . "\n";

            if ($cgi->param('translate'))
            {
                $treeData .= join("\n",
                     , $cgi->submit('add rules')
                     , $cgi->submit('check rules')
                     , $cgi->br
                     , ''
                     );
            }

            $treeData .= join( "\n",
                               $cgi->br,
                               "<a href='Html/help_for_assignments_and_rules.html'>Help on Assignments, Rules, and Checkboxes</a>",
                               ""
                             );
        }

        $treeData .= $cgi->end_form . "\n";
    }

#  'align' with less than 2 sequences checked

} elsif ( $cgi->param('align') ) {

    print $cgi->header;
    $treeData .= "<h1>You need to check at least two sequences</h1>\n";

} elsif ($cgi->param('get sequences')) {

#==============================================================================
#  get sequences
#==============================================================================
    print $cgi->header;
    my ($prot, $seq, $desc, $org, $i);
    $treeData .= "<pre>\n";
    foreach $prot ( @checked ) {
        if ($seq = $fig->get_translation($prot))
        {
            $desc = $fig->function_of( $prot, $user );
            $org = $fig->org_of($prot);
            if ( $org ) { $desc .= " [$org]" }
            $treeData .= ">$prot $desc\n";
            for ($i=0; ($i < length($seq)); $i += 60)
            {
                $treeData .= substr($seq,$i,60) . "\n";
            }
        }
    }

    $treeData .=  "</pre>\n";
} elsif ($cgi->param('add rules') && (@checked > 0)) {

#==============================================================================
#  add rules
#==============================================================================

    print $cgi->header;
    my $to_func;
    my($from,$to,%tran,$line);

    if ((@from == 1) && ($from[0] =~ /^fig/) &&
        ($to_func = $fig->translate_function(scalar $fig->function_of($from[0]))))
    {
        my $col_hdrs = ["from","to"];
        my $tab = [];
        my($from_func,$peg);
        foreach $peg (@checked)
        {
            if (($from_func = $fig->translate_function(scalar $fig->function_of($peg))) &&
                ($from_func ne $to_func))
            {
                $tran{$from_func} = $to_func;
                push(@$tab,[$from_func,$to_func]);
            }
        }

        if (@$tab > 0)
        {
            $alignData .= join("\n", &HTML::make_table($col_hdrs,$tab,"Added Translation Rules"));

            if (open(TMP,"<$FIG_Config::global/function.synonyms")) {
                while (defined($line = <TMP>))
                {
                    chomp $line;
                    ($from,$to) = split(/\t/,$line);
                    if (($from ne $to) && (! $tran{$to}))
                    {
                        $tran{$from} = $to;
                    }
                }
                close(TMP);

                foreach $from (keys(%tran))
                {
                    $to = $tran{$from};
                    while ($tran{$to})
                    {
                        $to = $tran{$to};
                    }
                    $tran{$from} = $to;
                }
            }

            if (open(TMP,">$FIG_Config::global/function.synonyms"))
            {
                foreach $from (sort keys(%tran))
                {
                    print TMP "$from\t$tran{$from}\n";
                }
                close(TMP);
            }
            else
            {
                $alignData .= $cgi->h1("sorry, could not open function.synonyms; call support") . "\n";
            }
        }
    }
} elsif ($cgi->param('check rules')) {

#==============================================================================
#  check rules
#==============================================================================

    print $cgi->header;
    my($to_func,@rules,$i,$col_hdrs,$tab);
    if (! ($to_func = $cgi->param('to_func')))
    {
        if ($to_func = $fig->translate_function(scalar $fig->function_of($from[0])))
        {
            @rules = &rules_to($to_func);
            if (@rules > 0)
            {
                my $sprout = $cgi->param('SPROUT') ? 1 : "";

                $formData .= join("\n",$cgi->start_form(-method => 'post', -action => 'fid_checked.cgi'),
                            $cgi->hidden(-name => 'check rules', -value => 1,-override => 1),
                            $cgi->hidden(-name => 'SPROUT', -value => $sprout),
                            $cgi->hidden(-name => 'to_func',-value => $to_func, -override => 1),
                            "");

                $col_hdrs = ["delete","from","to"];
                $tab = [];
                for ($i=0; ($i < @rules); $i++)
                {
                    push(@$tab,[$cgi->checkbox(-name => 'rule_delete', -value => $i, -checked => 0, -label => ''),@{$rules[$i]}]);
                }
                $formData .= &HTML::make_table($col_hdrs,$tab,"Check Those to be Deleted") . "\n";
                $formData .= join("\n",$cgi->submit('delete'), $cgi->end_form, "");
            }
        }
        if (! $formData)
        {
            $alignData .= $cgi->h1("Sorry, no rules match") . "\n";
        }
    }
    else
    {
        my @rule_delete = $cgi->param('rule_delete');
        if (@rule_delete > 0)
        {
            &delete_rules($to_func,\@rule_delete);
            $alignData .= $cgi->h1("Done") . "\n";
        }
        else
        {
            $alignData .= $cgi->h1("Sorry, you need to select rules to be deleted") . "\n";
        }
    }
} elsif ($cgi->param('show regions') && (@checked > 1)) {

#==============================================================================
#  show regions
#==============================================================================

    my $pinned_to = "pinned_to=" . join("&pinned_to=",@checked);
    my $sprout = $cgi->param('SPROUT') ? 1 : "";
    $ENV{"REQUEST_METHOD"} = "GET";
    $ENV{"QUERY_STRING"} = "user=$user&$pinned_to&SPROUT=&sprout";
    my @out = `$ENV{KB_TOP}/cgi-bin/chromosomal_clusters.cgi`;
    print join("",@out);
    exit;
} elsif ($cgi->param('view annotations') && (@checked > 0)) {

#==============================================================================
#  view annotations
#==============================================================================
    print $cgi->header;
    my $col_hdrs = ["who","when","annotation"];
    $alignData .= join("\n", "<table border=\"2\" align=\"center\">",
                             $cgi->Tr($cgi->th({ align => "center" }, $col_hdrs)),
                             "");
    foreach my $fid (@checked) {

        my $tab = [ map { [$_->[2],$_->[1],$_->[3]] } $fig->feature_annotations($fid) ];
        my $title = (@$tab == 0 ? "No " : "") . "Annotations for $fid";
        $alignData .= join("\n", $cgi->Tr($cgi->td({ colspan => 3, align => "center" }, $title)), "");
        if (@$tab > 0) {
            for my $row (@$tab) {
                $alignData .= $cgi->Tr($cgi->td($row));
            }
        }
    }
    $alignData .= "</table>\n";

} elsif ($cgi->param('Align DNA') && (@checked > 0)) {

#==============================================================================
#  Align DNA
#==============================================================================

    my $upstream = $cgi->param('upstream');
    if (! defined($upstream))   { $upstream = 0 }

    my $coding   = $cgi->param('gene');
    if (! defined($coding)) { $coding = "" }
    $ENV{'QUERY_STRING'} = join("&",map { "peg=$_" } grep { $_ =~ /^fig/ } @checked) .
                           "&upstream=$upstream&gene=$coding";
    $ENV{'REQUEST_METHOD'} = 'GET';
    print `./align_DNA.cgi`;
    return;

} elsif ($cgi->param('Merge FigFams') && $user) {

#==============================================================================
#  Merge FigFams
#  Yes, this does not deal with fids, but the form points here. MJD
#==============================================================================

    print $cgi->header;

    my @figfams = grep {/^FIG\d+$/} @checked_figfam;

    if ( @figfams <= 1 ) {
	print "<h2>Please select two or more FigFam IDs whose families you wish to be merged</h2>\n";
	print "<p>FigFam IDs selected: " . join(", ", @figfams) . ".</p>\n";
    } else {
	print "<h2>Merging FigFams</h2>\n";
	print "<p>FigFam IDs selected: " . join(", ", @figfams) . ".</p>\n";

	use FFs;
	my $ffs = new FFs($FIG_Config::FigfamsData);

	if ( $ffs->merge_figfams(\@figfams, $user) ) {
	    print "<p>OK</p>\n";
	} else {
	    print "<p><h2>FAILED! Could not merge figfams -- contact seedtech and let us know<h2></p>\n";
	}
    }

    exit;

} elsif ($cgi->param('assign/annotate') && (@checked > 0) && $user) {

#==============================================================================
#  assign/annotate
#==============================================================================

    print $cgi->header;
    my $from = $from[0];
    my $func;
    if ( defined( $from ) && ( $func = $fig->function_of( $from, $user ) ) )
    {
	$func =~ s/\s+\#\s.*$//;    # Remove nonheritable comment

        my $fid = $cgi->param( 'fid' );

        my @my_checked = grep { $_ ne $from } @checked;
        my $anno = $cgi->param( 'tree_format' ) ? "Assignment projected from $from based on tree proximity"
                 : $cgi->param( 'from_sims' )   ? "Assignment projected from $from based on similarity"
                 :                                "Assignment projected from $from";
        my $assign_opts = { annotation => $anno, return_value => 'all_lists' };
        my ( @succ, @fail, @moot );

        #  In similarities, $fid has a special role as reference for projections:

        if ( $fid && ( $fid ne $from ) && $cgi->param( 'from_sims' ) )
        {
            #  We will build annoations that say that the assignment went from $from
            #  to $fid (by similarity) and then from $fid to the other features (also by
            #  similarity).
            if (  grep { $_ eq $fid } @my_checked )
            {
                my ( $s, $f, $m ) = $fig->assign_function( $fid, $user, $func, $assign_opts );
                push @succ, @$s;
                push @fail, @$f;
                push @moot, @$m;

                $assign_opts->{ annotation } = "Assignment projected from $fid based on similarity";
                @my_checked = grep { $_ ne $fid } @my_checked;
            }
            #  The difference here is that the similarity is from $from, through $fid, but there
            #  is nothing that ensures that $fid will have the same function, so we cannot say
            #  that the annotation of the rest of the genes came "from" $fid, even though it is
            #  the source of the similarities.
            else
            {
                $assign_opts->{ annotation } = "Assignment projected from $from based on indirect similarity through $fid";
            }
        }

        if ( @my_checked )
        {
            my ( $s, $f, $m ) = $fig->assign_function( \@my_checked, $user, $func, $assign_opts );
            push @succ, @$s;
            push @fail, @$f;
            push @moot, @$m;
        }

        $alignData .= "Function changed for: "              . join(  ', ', @succ ) . "<BR />\n" if @succ;
        $alignData .= "<B>Function change failed for:</B> " . join(  ', ', @fail ) . "<BR />\n" if @fail;
    }

    #  Produce an annotation form:
    else
    {
        $alignData .= join("\n", "<table border=1>",
                      "<tr><td>Protein</td><td>Organism</td><td>Current Function</td><td>By Whom</td></tr>",
                      "");
        my $defaultann=''; # this will just be the last function with BUT NOT added if we are negating the function
        foreach my $peg ( @checked ) {
            my @funcs = $fig->function_of( $peg );
            if ( ! @funcs ) { @funcs = ( ["", ] ) }
            my $nfunc = @funcs;
            my $org = $fig->org_of( $peg );
            $alignData .= join("\n", "<tr>",
                          "<td rowspan=$nfunc>$peg</td>",
                          "<td rowspan=$nfunc>$org</td>",
                          ""
                );
            my ($who, $what);
            $alignData .=  join( "</tr>\n<tr>", map { ($who,$what) = @$_; "<td>$what</td><td>$who</td>" } @funcs );
            $alignData .= "</tr>\n";
            if ($cgi->param("negate")) {$defaultann="$what BUT NOT"}
        }
        $alignData .= "</table>\n";

        my $sprout = $cgi->param('SPROUT') ? 1 : "";
        $formData .= join("\n", $cgi->start_form(-action => "fid_checked.cgi"),
                      $cgi->br, $cgi->br,
                      ("<br><a href='Html/seedtips.html#gene_names' class='help' target='help'>Help on Annotations</a>"),
                      "<table>",
                      "<tr><td>New Function:</td>",
                      "<td>", $cgi->textfield(-name => "function", -default=>$defaultann, -size => 60), "</td></tr>",
                      "<tr><td colspan=2>", $cgi->hr, "</td></tr>",
                      "<tr><td>New Annotation:</td>",
                      "<td rowspan=2>", $cgi->textarea(-name => "annotation", -rows => 30, -cols => 60), "</td></tr>",
                      "<tr><td valign=top><br>", $cgi->submit('add annotation'), "</td></tr>",
                      "</table>",
                      $cgi->hidden(-name => 'user', -value => $user),
                      $cgi->hidden(-name => 'SPROUT', -value => $sprout),
                      $cgi->hidden(-name => 'checked', -value => [@checked]),
                      $cgi->end_form,
                      ""
             );
    }
} elsif ($cgi->param('batch_assign') && (@checked > 0) && $user) {


#==============================================================================
#  batch assign
#
# This comes from the "show missing including matches" code in ssa2.cgi.
#
# Modified by RAE to allow from=(.*) to be a peg or a function, and used in
# check_subsys.cgi
#
#==============================================================================

    print $cgi->header;
    $alignData .= "<h2>Batch Assignments Made:\n";
    for my $ent (@checked)
    {
        if ($ent =~ /^to=(.*),from=(.*)$/)
        {
            my $to_peg = $1;
            my $from_peg = $2;

            # RAE: I only changed this line below
            # my $from_func = $fig->function_of($from_peg);
            my $from_func = ($from_peg =~ /\|/) ? $fig->function_of($from_peg) : $from_peg;

            next unless $from_func;

            my $link = &HTML::fid_link($cgi, $to_peg, 0);
            $alignData .= "User $user assigning $from_func to $link<br>\n";
            $fig->assign_function($to_peg,$user,$from_func,"");
        }
    }
    $alignData .= $cgi->h1("Done");
} elsif ($cgi->param("lock_annotations") && (@checked > 0) && $user)
{
#==============================================================================
#  lock annotation
#==============================================================================

    print $cgi->header;
    my $userR = ($user =~ /^master:(.*)/) ? $1 : $user;
    foreach my $peg (@checked)
    {
	$fig->lock_fid($user,$peg);
    }
    $alignData .= $cgi->h1("Done") . "\n";

} elsif ($cgi->param("unlock_annotations") && (@checked > 0) && $user)
{
#==============================================================================
#  unlock annotations
#==============================================================================

    print $cgi->header;
    my $userR = ($user =~ /^master:(.*)/) ? $1 : $user;
    foreach my $peg (@checked)
    {
	$fig->unlock_fid($user,$peg);
    }
    $alignData .= $cgi->h1("Done") . "\n";

#==============================================================================
#  add annotation
#
#  2012-11-21  Annotations will only be added to explicitly identified
#              features; there is no projection by md5 or solid rectangles.
#==============================================================================

} elsif ($cgi->param("add annotation") && (@checked > 0) && $user &&
    ($function || ($annotation = $cgi->param('annotation')))) {

    print $cgi->header;

    if ( $function )
    {
        my $assign_opt = { return_value => 'all_lists' };
        my ( $succ, $fail, $moot ) = $fig->assign_function( \@checked, $user, $function, $assign_opt );
        $alignData .= "Function changed for: "              . join(  ', ', @$succ ) . "<BR />\n" if @$succ;
        $alignData .= "<B>Function change failed for:</B> " . join(  ', ', @$fail ) . "<BR />\n" if @$fail;
    }

    if ( $annotation )
    {
        my $userR = $user;
        $userR =~ s/^master://i;
        foreach my $fid ( @checked )
        {
            $fig->add_annotation( $fid, $userR, "$annotation\n" );
        }
        $alignData .= "Annotation added for: " . join(  ', ', @checked ) . "<BR />\n" if @checked;
    }

#==============================================================================
#  Similarities form
#==============================================================================

} elsif ( $cgi->param("view similarities") && ( @checked > 0 ) ) {

    print $cgi->header;
    my $sprout = $cgi->param('SPROUT') ? 1 : "";

    $formData .= join("\n", $cgi->start_form( -method => 'post',
                                   -target => "sims_window$$",
                                   -action => 'protein.cgi#Similarities',
                                 ),
                 $cgi->hidden( -name => 'SPROUT', -value => $sprout ),
                 $cgi->hidden( -name => 'sims',   -value => 1 ),
                 $cgi->hidden( -name => 'user',   -value => $user ),
                 "");

    $formData .= <<'End_Sims_Options';
        <H2>Similarities Option Settings</H2>

        Max sims:<input   type=text name=maxN       size=5 value=50   > &nbsp;&nbsp;
        Max expand:<input type=text name=max_expand size=5 value=5    > &nbsp;&nbsp;
        Max E-val:<input  type=text name=maxP       size=8 value=1e-05> &nbsp;&nbsp;
        <select name=select>
            <option value=all selected >Show all databases</option>
            <option value=fig_pref     >Prefer FIG IDs (to max exp)</option>
            <option value=figx_pref    >Prefer FIG IDs (all)</option>
            <option value=fig          >Just FIG IDs (to max exp)</option>
            <option value=figx         >Just FIG IDs (all)</option>
        </select> &nbsp;&nbsp;
        Show Env. samples:<input type=checkbox name=show_env   value=1> &nbsp;&nbsp;
        Hide aliases:<input      type=checkbox name=hide_alias value=1><br />

        Sort by
        <select name=sort_by>
            <option value=bits selected >score</option>
            <option value=id2           >percent identity*</option>
            <option value=bpp2          >score per position*</option>
            <option value=id            >percent identity</option>
            <option value=bpp           >score per position</option>
        </select> &nbsp;&nbsp;
        Group by genome:<input type=checkbox name=group_by_genome value=1 > &nbsp;&nbsp;&nbsp;
        <A href="Html/similarities_options.html" target="SEED_or_SPROUT_help">Help with SEED similarities options</A><br />
        <input type=hidden name=extra_opt value="1">

        Min similarity:<input type=text name=min_sim size=5 value=0>
        defined by
        <select name=sim_meas>
            <option value=id  selected >identities (0-100%)</option>
            <option value=bpp >score per position (0-2 bits)</option>
        </select> &nbsp;&nbsp;
        Min query cover (%):<input type=text name=min_q_cov size=5 value=0> &nbsp;&nbsp;
        Min subject cover (%):<input type=text name=min_s_cov size=5 value=0><p />

End_Sims_Options

    my $col_hdrs = [ 'Query sequence', 'Organism', 'Assignment' ];
    my $tab = [];
    foreach my $peg ( @checked )
    {
        push @$tab, [ $cgi->submit("prot", $peg),
                      "&nbsp;" . $fig->genus_species( $fig->genome_of( $peg ) ) . "&nbsp;",
                      "&nbsp;" . scalar $fig->function_of( $peg, $user ) . "&nbsp;"
                    ];
    }

    $formData .= join("\n", HTML::make_table( $col_hdrs, $tab, "Links to Protein Similaries" ),
                 $cgi->end_form, "");

} else {

#==============================================================================
#  failure
#==============================================================================

    print $cgi->header;
    $alignData .= $cgi->h1("invalid request");
}
$to->add(form  => $formData);
$to->add(align => $alignData);
$to->add(tree  => $treeData);
$to->add(param => $paramData);

print $to->finish();


#==============================================================================
#  Only subroutines below
#==============================================================================
#  This is a sufficient set of escaping for text in HTML (function and alias):
#
#     $html = html_esc( $text )
#------------------------------------------------------------------------------

sub html_esc { local $_ = $_[0]; s/\&/&amp;/g; s/\>/&gt;/g; s/\</&lt;/g; $_ }


sub rules_to {
    my($to_func) = @_;

    my @rules = ();
    if (open(TMP,"<$FIG_Config::global/function.synonyms"))
    {
        my($line,$from,$to);
        while (defined($line = <TMP>))
        {
            chomp $line;
            ($from,$to) = split(/\t/,$line);
            if ($to eq $to_func)
            {
                push(@rules,[$from,$to]);
            }
        }
        close(TMP);
    }
    return @rules;
}

sub delete_rules {
    my($to_func,$which) = @_;

    my $to_funcQ = quotemeta $to_func;
    my $file = "$FIG_Config::global/function.synonyms";
    if ((rename($file,"$file~")) && open(TMPIN,"<$file~") && open(TMPOUT,">$file"))
    {
        my $n = 0;
        my($line,$i);
        while (defined($line = <TMPIN>))
        {
            if ($line =~ /\t$to_funcQ$/)
            {
                for ($i=0; ($i < @$which) && ($which->[$i] != $n); $i++) {}
                if ($i == @$which)
                {
                    print TMPOUT $line;
                }
                $n++;
            }
            else
            {
                print TMPOUT $line;
            }
        }
        close(TMPIN);
        close(TMPOUT);
        chmod 0777, $file, "$file~";
    }
    else
    {
        print STDERR "Failed to rename $file\n";
    }
}


#
#   @ids = read_cached_ids( $cache );
#  \@ids = read_cached_ids( $cache );
#
sub read_cached_ids
{
    my $cache = shift;
    my @ids;
    if ( open( IDS, "<$FIG_Config::temp/$cache.ids" ) )
    {
        @ids = grep { /\S/ } map { chomp; $_ } <IDS>;
        close( IDS );
    }
    wantarray ? @ids : \@ids;
}


#
#  write_cached_ids( $cache,  @ids );
#  write_cached_ids( $cache, \@ids );
#
sub write_cached_ids
{
    my $cache = shift;
    if ( open( IDS, ">$FIG_Config::temp/$cache.ids" ) )
    {
        foreach ( ref($_[0]) ? @{$_[0]} : @_ ) { print IDS "$_\n" if $_ }
        close( IDS );
    }
}


#
#   @alignment = read_cached_align( $cache );
#  \@alignment = read_cached_align( $cache );
#
sub read_cached_align
{
    my $cache = shift;
    gjoseqlib::read_fasta( "$FIG_Config::temp/$cache.align" );
}


#
#  write_cached_align( $cache,  @alignment );
#  write_cached_align( $cache, \@alignment );
#
sub write_cached_align
{
    my $cache = shift;
    my $file = "$FIG_Config::temp/$cache.align";
    gjoseqlib::print_alignment_as_fasta( $file, @_ );
}


#
#  $tree = read_cached_tree( $cache );
#
sub read_cached_tree
{
    my $cache = shift;
    gjonewicklib::read_newick_tree( "$FIG_Config::temp/$cache.newick" );
}


#
#  write_cached_tree( $cache, $tree );
#
sub write_cached_tree
{
    my ( $cache, $tree ) = @_;
    my $file = "$FIG_Config::temp/$cache.newick";
    gjonewicklib::writeNewickTree( $tree, $file );
}

##################################################

sub to_clustal {
    my($alignment) = @_;

    my($tuple,$seq,$i);
    my $len_name = 0;
    foreach $tuple (@$alignment)
    {
	my $sz = length($tuple->[0]);
	$len_name = ($sz > $len_name) ? $sz : $len_name;
    }

    my @seq  = map { $_->[2] } @$alignment;
    my $seq1 = shift @seq;
    my $cons = "\377" x length($seq1);
    foreach $seq (@seq)
    {
	$seq  = ~($seq ^ $seq1);
	$seq  =~ tr/\377/\000/c;
	$cons &= $seq;
    }
    $cons =~ tr/\000/ /;
    $cons =~ tr/\377/*/;

    push(@$alignment,["","",$cons]);

    my @out = ();
    for ($i=0; ($i < length($seq1)); $i += 50)
    {
	foreach $tuple (@$alignment)
	{
	    my($id,undef,$seq) = @$tuple;
	    my $line = sprintf("%-" . $len_name . "s",$id) . " " . substr($seq,$i,50) . "\n";
	    push(@out,$line);
	}
	push(@out,"\n");
    }
    return join("","CLUSTAL W (1.8.3) multiple sequence alignment\n\n\n",@out);
}


