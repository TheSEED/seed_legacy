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

####################

require Time::HiRes;
#tick('start');

# use CGI ':standard';  # Included by FIG_CGI
use FIG;
use FIG_CGI;
use FIGjs;
use Fcntl qw/:flock/;  # import LOCK_* constants
use Tracer;
use FidCheck;
use FIGRules;
use HTML;
use strict;
use GenoGraphics;
use LWP::UserAgent;
use URI::Escape;
use FFs;
use Carp;

#tick('top');

my ( $fig, $cgi, $user ) = FIG_CGI::init( debug_save   => 0,
                                          debug_load   => 0,
                                          print_params => 0
                                        );

if (0) {
    my $VAR1;
    eval(join("",`cat /tmp/protein_parms`));
    $cgi = $VAR1;
#   print STDERR &Dumper($cgi);
}

if (0) {
    print $cgi->header;
    my @params = $cgi->param;
    print "<pre>\n";
    foreach $_ (@params) {
                print "$_\t:",join(",",$cgi->param($_)),":\n";
    }

    if (0) {
        if (open(TMP,">/tmp/protein_parms")) {
                print TMP &Dumper($cgi);
                close(TMP);
                }
    }
    exit;
}

&main_routine( $fig, $cgi, $user );


#  Everything below here is subroutines. =======================================

sub main_routine
{
    my ( $fig, $cgi, $user ) = @_;
    my $html = [];

    my $db_title = $fig->Title();
    unshift @$html, "<TITLE>The $db_title Chromosomal Clusters Page</TITLE>\n";

    push @$html, &FIGjs::toolTipScript() . "\n";

    my $request     = $cgi->param('request') || '';
    my $SproutValue = $cgi->param('SPROUT') ? "1" : "";

    if ($request eq "figfam")
    {
        if ( eval { require FF; } )
        {
            my $fam = $cgi->param('fam');
            my $famO = new FF( $fam, "$FIG_Config::FigfamsData" );
            my $func = $famO->family_function('full');
            push( @$html, $func ? $cgi->h1($func) : "Sorry, could not locate data for $fam" );
        }
        else
        {
            push( @$html, "<H2>Failed in require of FF.pm</H2>\n");
        }
        my_show_page( $SproutValue, $cgi, $html );
        return;
    }

    if ($request eq "show_commentary")
    {
        &show_commentary($fig,$cgi,$html);
        my_show_page( $SproutValue, $cgi, $html );
        return;
    }

    my $new_sub;
    if ($cgi->param('Generate Cluster-Based Subsystem') && ($new_sub = $cgi->param('new_subsys')))
    {
        &generate_subsystem($fig,$cgi,$user,$html,$new_sub);
     #  print $cgi->redirect("http://anno-3.nmpdr.org/anno/FIG/subsys.cgi?ssa_name=$new_sub&user=$user&request=show_ssa&can_alter=1&show_clusters=1");
        print $cgi->redirect("http://anno-3.nmpdr.org/anno/FIG/SubsysEditor.cgi?page=ShowSubsystem&subsystem=$new_sub&user=$user");
        return;
    }

    #
    # Check our varous caches.
    #

    if ( ! $cgi->param('prot') )
    {
        push( @$html, "<H2>chromosomal_clusters requires a 'request' or a 'prot'.</H2>\n");
        my_show_page( $SproutValue, $cgi, $html );
        return;
    }

    my $sim_cutoff = $cgi->param('sim_cutoff') || 1.0e-20;

    {
        my $prot = $cgi->param('prot');
        if ($prot =~ /^fig\|\d+\.\d+\.peg\.\d+$/)
        {
            if (0 && &handled_by_local_cache($fig, $cgi, $prot, $sim_cutoff))
            {
                #tick("exit 1");
                return;
            }

            if (&handled_by_precomputed_pin($fig, $cgi, $html, $prot, $sim_cutoff))
            {
                #tick("exit 2");
                return;
            }

    #       if (&handled_by_clearinghouse_image_cache($fig, $cgi, $user, $prot, $sim_cutoff))
    #       {
    #           tick("exit 3");
    #           return;
    #       }
        }
    }

    #
    # No caching worked, compute.
    #
    warn "computing pin\n";
    $| = 1;

    print "Content-type: multipart/x-mixed-replace;boundary=NEXT\n";
    print "\n";
    print "--NEXT\n";
    {
        my $h = ["<h1>Computing pins, please wait...</h1>\n"];
        my_show_page( $SproutValue, $cgi, $h );
        print "--NEXT\n";
    }

    my( $prot, $pinned_to, $in_pin, $uniL, $uniM ) = get_prot_and_pins( $fig, $cgi, $html );
    return unless $prot;

    Trace("Pin list has " . scalar(@$pinned_to) . " pegs.") if T(3);
    my( $gg, $all_pegs, $pegI ) = get_initial_gg_and_all_pegs( $fig, $cgi, $prot, $pinned_to, $uniL, $uniM );
    Trace("GG has " . scalar(@$gg) . " elements. All-pegs has " . scalar(@$all_pegs) . " elements.") if T(3);
    add_change_sim_threshhold_form( $cgi, $html, $prot, $pinned_to );

    my( $color, $text ) = form_sets_and_set_color_and_text( $fig, $cgi, $gg, $pegI, $all_pegs, $sim_cutoff );
    if (T(3)) {
        Trace("GG has " . scalar(@$gg) . " elements after color computation.");
        if (! defined($color)) {
            Trace("No colors returned.");
        } elsif (ref $color eq 'ARRAY') {
            Trace("Color array has " . scalar(@$color) . " elements.");
        } elsif (ref $color eq 'HASH') {
            Trace("Color hash has " . scalar(keys %$color) . " keys.");
        } else {
            Trace("Color is a scalar.")
        }
    }
    my $vals = update_gg_with_color_and_text( $cgi, $gg, $color, $text, $prot );
    Trace("GG has " . scalar(@$gg) . " elements after color update.") if T(3);

    if ( @$gg == 0 )
    {
        push( @$html,$cgi->h1("Sorry, no pins worked out") );
    }
    else
    {
        &add_commentary_form( $cgi, $user, $html, $prot, $vals );
        &thin_out_over_max( $cgi, $html, $prot, $gg, $in_pin );
        Trace("GG has " . scalar(@$gg) . " elements after thinning.") if T(3);

        # As of May 8, 2005, we are going to start caching results, so all GenoGraphics images
        # are saved.  Hence, I am disposing of the "save" option.  RAO
        push( @$html, @{ &GenoGraphics::render( $gg, 1000, 4, 1 ) } );
        push( @$html,    &FIGGenDB::linkClusterGenDB($prot) );
    }

    &cache_html( $fig, $cgi, $html );
    my_show_page( $SproutValue, $cgi, $html );

    return;
}
#  End of main_routine() -------------------------------------------------------


sub generate_subsystem {
    my($fig,$cgi,$user,$html,$new_sub) = @_;

    if (! $user) { print STDERR "You cannot generate a subsstem without setting user\n"; return }
    if (($user =~ /^\S/) && ($user !~ /^master:/)) { $user = "master:$user" }
    $fig->set_user($user);

    my %roleN    = map { $_ => 1 } $cgi->param('roles');
    my @tuples   = map { (($_ =~ /^(fig\|\d+\.\d+\.peg\.\d+):(\d+)/) && $roleN{$2}) ? [$1,$2] : () }
                   $cgi->param('text');

    my @role_tuples = ();
    my %role_index;
    my %genomes;
    my %cell;

    my $rN = 1;
    my %funcs;
    foreach my $n (sort { $a <=> $b } keys(%roleN))
    {
	my @pegs = map { ($_->[1] == $n) ? $_->[0] : () } @tuples;

	foreach my $peg (@pegs)
	{
	    $genomes{&FIG::genome_of($peg)} = 1;
	    my $func = $fig->function_of($peg,1);
	    if ($func)
	    {
		my @role_set = split(/\s*;\s+|\s+[\@\/]\s+/,$func);
		foreach my $role (@role_set)
		{
		    $funcs{$role}++;
		    push(@{$cell{&FIG::genome_of($peg)}->{$role}},$peg);
		}
	    }
	}
    }

    foreach my $role (sort { $funcs{$b} <=> $funcs{$a} } keys(%funcs))
    {
	push(@role_tuples,[$role,"R$rN"]);
	$role_index{$role} = "R$rN";

	$rN++;
    }

    my @sorted_genomes = sort { $a <=> $b } keys(%genomes);
    my $subO = new Subsystem($new_sub,$fig,'create');
    $subO->set_roles(\@role_tuples);
    foreach my $genome (@sorted_genomes)
    {
	$subO->add_genome($genome);
	my $x = $cell{$genome};
	foreach my $y (keys(%$x))
	{
	    my $roleA = $role_index{$y};
	    $subO->set_pegs_in_cell($genome,$roleA,[sort @{$x->{$y}}]);
	}
    }
    $subO->write_subsystem;
}

sub pick_color {
    my( $cgi, $all_pegs, $color_set, $i, $colors ) = @_;
    my $retVal;
    if ( @$colors > 0 )
    {
        my( $j, $peg, $color );
        my %colors_imported = map { ( $peg, $color ) = $_ =~ /^(.*):([^:]*)$/ } @$colors;
        for ($j=0; ($j < @$color_set) && (! $colors_imported{$all_pegs->[$color_set->[$j]]}); $j++) {}
        if ($j < @$color_set)
        {
            $retVal = $colors_imported{$all_pegs->[$color_set->[$j]]};
            return $retVal;
        }
    }
    $retVal = ( $i == 0 ) ? "red" : "color$i";
    return $retVal;
}

sub pick_text {
    my($cgi,$all_pegs,$color_set,$i,$texts) = @_;
    my($peg,$text,$j);

    if (@$texts > 0)
    {
        my %texts_imported = map { ($peg,$text) = split(/:/,$_); $peg => $text } @$texts;
        for ($j=0; ($j < @$color_set) && (! $texts_imported{$all_pegs->[$color_set->[$j]]}); $j++) {}
        if ($j < @$color_set)
        {
            return $texts_imported{$all_pegs->[$color_set->[$j]]};
        }
    }
    return $i+1;
}

sub in {
    my( $x, $xL ) = @_;

    foreach ( @$xL ) { if ( $x == $_ ) { return 1 } }
    return 0;
}

sub in_bounds {
    my($min,$max,$x) = @_;

    if     ($x < $min)     { return $min }
    elsif  ($x > $max)     { return $max }
    else                   { return $x   }
}

sub decr_coords {
    my($genes,$min) = @_;
    my($gene);

    foreach $gene (@$genes)
    {
        $gene->[0] -= $min;
        $gene->[1] -= $min;
    }
    return $genes;
}

sub flip_map {
    my($genes,$min,$max) = @_;
    my($gene);

    foreach $gene (@$genes)
    {
        ($gene->[0],$gene->[1]) = ($max - $gene->[1],$max - $gene->[0]);
        $gene->[2] = ($gene->[2] eq "rightArrow") ? "leftArrow" : "rightArrow";
    }
    return $genes;
}

sub gs_of {
    my($peg) = @_;

    $peg =~ /fig\|(\d+)/;
    return $1;
}


#  How about some color commentary?

sub show_commentary {
    my($fig,$cgi,$html) = @_;

    my(@vals,$val,%by_set,$col_hdrs,$tab,$n,$occ,$org,$fid,$ff,$set,$x,$i,%by_line,%fid_to_line,%ff_set);
    $cgi->delete('request');

    my $ffs = new FFs("$FIG_Config::FigfamsData");

    my $new_framework = $cgi->param('new_framework') ? 1 : 0;
    @vals = $cgi->param('show');
    # The list of FIDs we're looking at will go in here.
    my @fidList = ();
    # Loop through the incoming values.
    foreach $val (@vals)
    {
        ( $n, $i, $fid, $org, $occ ) = split( /\@/, $val );

	$ff = $ffs->family_containing_peg($fid) || '';
	$ff && ($ff_set{$n}{$ff} = 1);

        push( @{ $by_set{$n}  }, [ $i, $org, $occ, $fid, $ff ] );
        push( @{ $by_line{$i} }, $n );
        if ($n == 1) { $fid_to_line{$fid} = $i }
        push @fidList, $fid;
    }

    # Get all the evidence codes. The codes are used below, but it's tons faster to get them
    # all at once.
    my @evRows = $fig->get_attributes(\@fidList, "evidence_code");
    # Sort them by FID.
    my %evHash;
    for my $evCodeRow (@evRows) {
        my $fid = $evCodeRow->[0];
        if (exists $evHash{$fid}) {
            push @{$evHash{$fid}}, $evCodeRow;
        } else {
            $evHash{$fid} = [$evCodeRow];
        }
    }

    my($func,$user_entry,$func_entry,$target);

    my $user = $cgi->param('user');
    if ($user)
    {
        $target = "window$$";
	if (($user =~ /^\S/) && ($user !~ /^master:/)) { $user = "master:$user" }
	$fig->set_user($user);
    }

    foreach $set (sort { $a <=> $b } keys(%by_set))
    {
        if ($cgi->param('uni'))
        {
            $col_hdrs = ["Set","Organism","Occ","UniProt","UniProt Function","PEG","SS",
                          &evidence_codes_link($cgi),"Ln","Function","FF"];
        }
        else
        {
            $col_hdrs = ["Set","Organism","Occ","PEG","SS",&evidence_codes_link($cgi),"Ln","Function","FF"];
        }
        $tab = [];

        if ($user)
        {

            push(@$html,$cgi->start_form(-method => 'post',
                                         -target => $target,
                                         -name   => "form$set",
                                         -action => &FIG::cgi_url . "/fid_checked.cgi"),
                 $cgi->hidden(-name => 'new_framework', -value => $new_framework),
                 $cgi->hidden(-name => 'user', -value => $user)
                 );
        }

        #  For colorized functions we need to get the functions, then set the
        #  colors.  Given the structure of the current code, it seems easiest
        #  to accumulate the information on a first pass, exactly as done now,
        #  but then go back and stuff  the colors in (possibly even by keeping
        #  a stack of references to the ultimate locations).

        my( @uni, $uni_link, %uni_func );
        my @func_summary = ();
        my %func_count = ();
        my %order = ();
        my $cnt = 0;

	my $ff_set_count = exists $ff_set{$set}? scalar keys %{ $ff_set{$set} } : 0;
	my %ff_seen = ();

        foreach $x ( sort { ($a->[0] <=> $b->[0]) or ($a->[2] <=> $b->[2]) } @{ $by_set{$set} } )
        {
            ( undef, $org, $occ, $fid, $ff ) = @$x;
            my $tran_len = $fig->translation_length($fid);
            my @subs    = $fig->peg_to_subsystems($fid);
            #my $in_sub  = @subs;

            # RAE: Copied from protein.cgi
            my $in_sub;
            if ($cgi->param('SPROUT'))
            {
                $in_sub = @subs;
            }
            elsif (@subs > 0) {
                $in_sub = @subs;
                my $ss_list=join "<br>", map { my $g = $_; $g =~ s/\_/ /g; $_ = $g } sort {$a cmp $b} @subs;
                $in_sub = $cgi->a({id=>"subsystems", onMouseover=>"javascript:if(!this.tooltip) this.tooltip=new Popup_Tooltip(this, 'Subsystems', '$ss_list', ''); this.tooltip.addHandler(); return false;"}, $in_sub);
            }
            else
            {
                $in_sub = "&nbsp;";
            }

	    my $ff_ref  = '';

	    if ( $ff )
	    {
		if ( $ff_set_count == 0 )
		{
		    # this should not happen
		    $ff_ref = &ff_link($ff);
		}
		elsif ( $ff_set_count == 1 )
		{
		    $ff_ref = &ff_link($ff);
		}
		else
		{
		    if ( $user )
		    {
			if ( exists $ff_seen{$ff} )
			{
			    $ff_ref = &ff_link($ff);
			}
			else
			{
			    $ff_ref = $cgi->checkbox(-name => 'checked_figfam', -label => '', -value => $ff) . &ff_link($ff);
			    $ff_seen{$ff} = 1;
			}
		    }
		    else
		    {
			$ff_ref = &ff_link($ff);
		    }
		}
	    }

#            @uni = $cgi->param('uni') ? $fig->to_alias($fid,"uni") : "";
            @uni = $cgi->param('uni') ? $fig->uniprot_aliases($fid) : ();
	
	    # sorting will bring sp before tr before uni ids
	    @uni = sort @uni;

	    my $not_found = 1;
	    my $j;
	    for ($j = 0; $j < @uni and $not_found; $j++)
	    {
		my $uni_id = $uni[$j];
		# check if function_of has already been called for $uni_id
		if ( ! exists $uni_func{$uni_id} ) {
		    $uni_func{$uni_id} = $fig->function_of($uni_id) || '';
		}

		# if a function was found for $uni_id, drop out of the loop, preserving the value of $j
		if ( $uni_func{$uni_id} ) {
		    $not_found = 0;
		    $j--;
		}
	    }
	
	    if ( @uni ) {
		if ( $j < @uni ) {
		    # a function was found for $uni[$j], display only this id on the web-page
		    @uni = @uni[$j];
		} else {
		    # no function was found for any of @uni, use the first id for display on the web-page
		    @uni = @uni[0];
		}
	    }

            $uni_link = join( ", ", map { &HTML::uniprot_link( $cgi, $_ ) } @uni );

            $user_entry = &HTML::fid_link( $cgi, $fid );

            if ($user)
            {
                $user_entry = $cgi->checkbox(-name => 'checked', -label => '', -value => $fid) . "&nbsp; $user_entry";
            }

            $func = $fig->function_of($fid,$cgi->param('user'));
            if ($user && $func)
            {
                $func_entry = $cgi->checkbox(-name => 'from', -label => '', -value => $fid) . "&nbsp; $func";
            }
            else
            {
                $func_entry = $func;
            }

            #  Record the count of each function, and the order of first occurance:

            if ( $func ) { ( $func_count{ $func }++ ) or ( $order{ $func } = ++$cnt ) }

            #  We need to build a table entry that HTML::make_table will color
            #  the cell.  It would certainly be possible to use the old colon
            #  delimited prefix.  Rob Edwards added the really nice feature that
            #  if the cell contents are a reference to an array, then the first
            #  element in the content, and the second element is the tag.  We
            #  Will till it in so that if nothing else happens it is fine.

            my $func_ref = [ $func_entry, "td" ];
            my $uni_ref  = undef;
            my $uni_func = undef;

	    my $ev = join("<br>", map {&HTML::lit_link($_)} &evidence_codes($fig, $fid, $evHash{$fid}));

            if ($cgi->param('uni'))
            {
                my $uni_entry;
                $uni_func = (@uni > 0) ? $fig->function_of($uni[0]) : "";
                if ( $uni_func && $user )
                {
                    $uni_entry = $cgi->checkbox(-name => 'from', -label => '', -value => $uni[0]) . "&nbsp; $uni_func";
                }
                else
                {
                    $uni_entry = $uni_func;
                }
                $uni_ref = [ $uni_entry, "td" ];
                push( @$tab,[ $set, $org, $occ, $uni_link, $uni_ref, $user_entry, $in_sub, $ev,$tran_len, $func_ref ,$ff_ref] );
            }
            else
            {
                push( @$tab, [ $set, $org, $occ, $user_entry, $in_sub, $ev, $tran_len, $func_ref, $ff_ref ] );
            }

            #  Remember the information we need to do the coloring:

            push @func_summary, [ $func, $func_ref, $uni_func, $uni_ref ];
        }

        #  Okay, let's propose some colors:

        my @colors = ("#EECCAA", "#FFAAAA", "#FFCC66", "#FFFF00",  "#AAFFAA", "#BBBBFF", "#FFAAFF"); # #FFFFFF
        my %func_color = map  { $_ => ( shift @colors || "#DDDDDD" ) }
                         sort { $func_count{ $b } <=> $func_count{ $a }
                             or      $order{ $a } <=> $order{ $b }
                              }
                         keys %func_count;

        my ( $row );
        foreach $row ( @func_summary )
        {
            my ( $func, $func_ref, $uni_func, $uni_ref ) = @$row;
            $func_ref->[1] = "td bgcolor=" . ( $func_color{ $func } || "#DDDDDD" );
            if ( $uni_ref )
            {
                $uni_ref->[1] = "td bgcolor=" . ( $func_color{ $uni_func } || "#DDDDDD" )
            }
        }

        push( @$html, &HTML::make_table( $col_hdrs, $tab, "Description By Set" ) );

        if ($user)
        {
            push(@$html,
                        &HTML::java_buttons("form$set", "checked"), $cgi->br,
                        $cgi->submit('assign/annotate'), "&nbsp;","&nbsp;","&nbsp;","&nbsp;",
                        $cgi->submit('Align DNA'),
                        ($ff_set_count > 1)? "&nbsp;&nbsp;&nbsp;&nbsp;" . $cgi->submit('Merge FIGfams') : '',
                        "&nbsp;","&nbsp;","Size upstream: ",
                        $cgi->textfield(-name => 'upstream', -size => 4, -value => 0),
                        "&nbsp;","&nbsp;",
                        "&nbsp;","&nbsp;", "Restrict coding area to (optional): ",
                        $cgi->textfield(-name => 'gene',   -size => 4, -value => "")
                );

            push(@$html,$cgi->end_form);
        }
    }


    #  Build a form for extracting subsets of genomes:

    $target = "window$$";
    my $SproutValue = $cgi->param('SPROUT') ? "1" : "";
    my $sim_cutoff  = $cgi->param('sim_cutoff') || 1.0e-20;
    push(@$html,$cgi->start_form(-method => 'post',
                                 -action => &FIG::cgi_url . "/chromosomal_clusters.cgi",
                                 -name   => "fid_checked",
                                 -target => $target),
                $cgi->hidden(-name => 'new_framework', -value => $new_framework),
                $cgi->hidden(-name => 'sim_cutoff', -value => $sim_cutoff),
                $cgi->hidden(-name => 'SPROUT', -value => $SproutValue));

    foreach $set (keys(%by_set))
    {
        my($x,$set0,$peg);
        $set0 = $set - 1;
        foreach $x (@{$by_set{$set}})
        {
            $peg = $x->[3];
            push(@$html,$cgi->hidden(-name => "color", -value => "$peg:color$set0"),
                        $cgi->hidden(-name => "text",  -value => "$peg:$set"));
        }
    }

    my $prot = $cgi->param('prot');

    $col_hdrs = ["show","map","genome","description","PEG","colors"];
    $tab      = [];
    $set      = $by_set{1};

    my %seen_peg;
    foreach $x (sort { $a->[1] cmp $b->[1] } @$set)
    {
        (undef,$org,undef,$fid) = @$x;
        next if ($seen_peg{$fid});
        $seen_peg{$fid} = 1;

        push(@$tab,[$cgi->checkbox(-name => 'pinned_to',
                                   -checked => 1,
                                   -label => '',
                                   -value => $fid),
                    $org,&FIG::genome_of($fid),$fig->org_of($fid),&HTML::fid_link($cgi,$fid),
                    join(",",sort { $a <=> $b } @{$by_line{$fid_to_line{$fid}}})
                   ]);
    }
    push(@$html,$cgi->hr);
    push (@$html, $cgi->br, &HTML::java_buttons("fid_checked", "pinned_to"), $cgi->br); # RAE: Add check all/none buttons

    push(@$html,&HTML::make_table($col_hdrs,$tab,"Keep Just Checked"),
                $cgi->hidden(-name => 'user', -value => $user),
#               $cgi->hidden(-name => 'prot', -value => $prot),
#               $cgi->hidden(-name => 'pinned_to', -value => $prot),
                $cgi->br,
                $cgi->submit('Picked Maps Only')
	);
    if ($user)
    {
	my @set_ids = sort { $a <=> $b } keys(%by_set);
	my $suggested = "";
	if ($prot && ($prot =~ /^fig\|(\d+\.\d+\.peg\.\d+)/))
	{
	    $suggested = "CBSS-$1";
	}

	push(@$html,$cgi->hr,$cgi->br,
	            "Subsystem Name: ",
	            $cgi->textfield(-name =>"new_subsys", -size => 80, -value => $suggested),$cgi->br,$cgi->br,
	            "Pick the color sets that you wish to become roles in the subsystem: ",$cgi->br,
	            $cgi->scrolling_list( -name     => 'roles',
					  -values   => [ @set_ids ],
					  -size     => 10,
					  -multiple => 1
					),
	            $cgi->br,
	            $cgi->submit('Generate Cluster-Based Subsystem'));
    }
    push(@$html,$cgi->end_form);
}


sub get_prot_and_pins
{
    my( $fig, $cgi, $html ) = @_;

    my $prot = $cgi->param('prot') || '';
    # RAE: added this so that you can paste spaces and get a resonable answer!
    $prot =~ s/^\s+//; $prot =~ s/\s+$//;

    my @pegs = map { split(/,/,$_) } $cgi->param('pinned_to');
    # RAE: remove leading and trailing spaces from IDs
    map {s/^\s+//; s/\s+$//} @pegs;
    my @nonfig = grep { $_ !~ /^fig\|/ } @pegs;
    my @pinned_to = ();

    my $uniL = {};
    my $uniM = {};

    if (@nonfig > 0)
    {
        my $col_hdrs = ["UniProt ID","UniProt Org","UniProt Function","FIG IDs","FIG orgs","FIG Functions"];
        my $tab = [];
        my $x;
        foreach $x (@nonfig)
        {
            if ($x =~ /^[A-Z0-9]{6}$/)
            {
                $x = "uni|$x";
            }
            my @to_fig = &resolve_id($fig, $x);
            my($fig_id,$fig_func,$fig_org);
            if (@to_fig == 0)
            {
                $fig_id = "No Matched FIG IDs";
                $fig_func = "";
                $fig_org = "";
                $x =~ /uni\|(\S+)/;
                $uniM->{$1} = 1;
            }
            else
            {
                $fig_id = join("<br>",map { &HTML::fid_link($cgi,$_) } @to_fig);
                $fig_func = join("<br>",map { $fig->function_of($_) } @to_fig);
                $fig_org  = join("<br>",map { $fig->org_of($_) } @to_fig);
                push(@pinned_to,@to_fig);
            }
            my $uni_org = $fig->org_of($x);
            push(@$tab,[&HTML::uni_link($cgi,$x),$fig->org_of($x),scalar $fig->function_of($x),$fig_id,$fig_org,$fig_func]);
        }
        push(@$html,$cgi->hr);
        push(@$html,&HTML::make_table($col_hdrs,$tab,"Correspondence Between UniProt and FIG IDs"));
        push(@$html,$cgi->hr);
    }
    else
    {
        @pinned_to = @pegs;
    }

    #  Make @pinned_to non-redundant by building a hash and extracting the keys

    my %pinned_to = map { $_ => 1 } @pinned_to;
    @pinned_to = sort { &FIG::by_fig_id($a,$b) } keys(%pinned_to);
    # print STDERR &Dumper(\@pinned_to);
    # tick(scalar(@pinned_to) . " pins found.");

    #  Do we have an explicit or implicit protein?

    if ((! $prot) && (@pinned_to < 2))
    {
        #push(@$html,"<h1>Sorry, you need to specify a protein</h1>\n");
        # RAE: A nicer rejection if no protein is specified. This will allow them to choose one or more pinned regions
        my $SproutValue = $cgi->param('SPROUT') ? "1" : "";
        push(@$html,
            $cgi->start_form, $cgi->p("Please enter an id of the protein to look at:", $cgi->textfield(-name=>"prot", -size=>40)),
            $cgi->p("You can also choose some other proteins to pin this to. Paste a comma separated list here: ",
                    $cgi->textfield(-name=>"pinned_to", -size=>80)),
            $cgi->hidden(-name => 'SPROUT', -value => $SproutValue),
            $cgi->submit, $cgi->reset, $cgi->end_form);
        my_show_page($SproutValue, $cgi,$html);
        return ();  # This is now handled by caller
    }

    #  No explicit protein, take one from the list:

    if (! $prot)
    {
        $prot = shift @pinned_to;
    }

    my $in_pin = @pinned_to;

    #  Make sure that there are pins

    if (@pinned_to < 1)
    {
        @pinned_to = &get_pin($fig, $prot);
        $in_pin = @pinned_to;
        my $max = $cgi->param('maxpin') || 300;
        if (@pinned_to > (2 * $max))
        {
            @pinned_to = &limit_pinned($prot,\@pinned_to,2 * $max);
        }
    }

#   print STDERR &Dumper(\@pinned_to);
    if (@pinned_to == 0)
    {
        push(@$html,"<h1>Sorry, protein is not pinned</h1>\nTry to establish coupling before displaying pinned region");
        my $SproutValue = $cgi->param('SPROUT') ? "1" : "";
        my_show_page($SproutValue, $cgi,$html);
        return ();  # This is now handled by caller
    }

    #  Ensure that there is exactly one copy of $prot, then sort by taxonomy:

    @pinned_to = ( $prot, grep { $_ ne $prot } @pinned_to );
    @pinned_to = $fig->sort_fids_by_taxonomy(@pinned_to);
#   print &Dumper([$prot,\@pinned_to,$in_pin]);

    #  $uniL is always {}.  What was it for? -- GJO
    return ( $prot, \@pinned_to, $in_pin, $uniL, $uniM );
}



sub get_initial_gg_and_all_pegs {
    my( $fig, $cgi, $prot, $pinned_to, $uniL, $uniM ) = @_;

    #  $prot       is the protein the reference protein
    #  @$pinned_to is the complete list of proteins to be aligned across genomes
    #  $uniL       is {} and is never used!
    #  %$uniM      is a hash of uniprot ids from $cgi->param('pinned_to'),
    #                  with no other information.  They create empty lines.

    my $gg = [];
    my($peg,$loc,$org,$contig,$beg,$end,$min,$max,$genes,$feat,$fid);
    my($contig1,$beg1,$end1,@all_pegs,$map,$mid,$pegI);
    foreach $peg ( @$pinned_to )
    {
        $org = $fig->org_of($peg);
#       print STDERR "processing $peg\n";
        $loc = $fig->feature_location($peg);
        if ( $loc)
        {
            ($contig,$beg,$end) = $fig->boundaries_of($loc);
            if ($contig && $beg && $end)
            {
                $mid = int(($beg + $end) / 2);
                $min = $mid - 8000;
                $max = $mid + 8000;
                $genes = [];
                ($feat,undef,undef) = $fig->genes_in_region(&FIG::genome_of($peg),$contig,$min,$max);
#               print STDERR &Dumper($feat);
                foreach $fid (@$feat)
                {
                    ($contig1,$beg1,$end1) = $fig->boundaries_of($fig->feature_location($fid));
#                   print STDERR "contig1=$contig1 beg1=$beg1 end1=$end1\n";
#                   print STDERR &Dumper([$fid,$fig->feature_location($fid),$fig->boundaries_of($fig->feature_location($fid))]);
                    $beg1 = &in_bounds($min,$max,$beg1);
                    $end1 = &in_bounds($min,$max,$end1);

                    #  Build the pop-up information for the gene:

                    my $function = $fig->function_of($fid);
                    my $aliases1 = $fig->feature_aliases($fid);
                    my ( $uniprot ) = $aliases1 =~ /(uni\|[^,]+)/;


                    my $info  = join( '<br/>', "<b>Org:</b> $org",
                                                "<b>PEG:</b> $fid",
                                               "<b>Contig:</b> $contig1",
                                               "<b>Begin:</b> $beg1",
                                               "<b>End:</b> $end1",
                                               ( $function ? "<b>Function:</b> $function" : () ),
                                               ( $uniprot ? "<b>Uniprot ID:</b> $uniprot" : () )
                                    );

                    #my @allattributes=$fig->get_attributes($fid);
                    #foreach my $eachattr (@allattributes) {
                #       my ($gotpeg,$gottag,$val, $url)=@$eachattr;
                #       $info .= "<br/><b>Attribute:</b> $gottag $val $url";
                #    }

                    push( @$genes, [ &FIG::min($beg1,$end1),
                                     &FIG::max($beg1,$end1),
                                     ($beg1 < $end1) ? "rightArrow" : "leftArrow",
                                     "",
                                     "",
                                     $fid,
                                     $info
                                   ] );

                    if ( $fid =~ /peg/ ) { push @all_pegs, $fid }
                }

                #  Everything is done for the one "genome", push it onto GenoGraphics input:
                #  Sequence title can be replaced by [ title, url, popup_text, menu, popup_title ]

                my $org = $fig->org_of( $peg );
                my $desc = "Genome: $org<br />Contig: $contig";
                $map = [ [ FIG::abbrev( $org ), undef, $desc, undef, 'Contig' ],
                         0,
                         $max+1-$min,
                         ($beg < $end) ? &decr_coords($genes,$min) : &flip_map($genes,$min,$max)
                       ];

                push( @$gg, $map );
            }
        }
    }

    &GenoGraphics::disambiguate_maps($gg);

    #  %$uniM is a hash of uniprot IDs.  This just draws blank genome lines for each.

    foreach $_ (sort keys %$uniM )
    {
        push( @$gg, [ $_, 0, 8000, [] ] );
    }
#   print STDERR &Dumper($gg); die "abort";

    #  move all pegs from the $prot genome to the front of all_pegs.

    my $genome_of_prot = $prot ? FIG::genome_of( $prot ) : "";

    if ( $genome_of_prot ) {
        my @tmp = ();
        foreach $peg ( @all_pegs )
        {
            if ( $genome_of_prot eq FIG::genome_of( $peg ) ) { unshift @tmp, $peg }
            else                                             { push    @tmp, $peg }
        }
        @all_pegs = @tmp;
    }

    #  Find the index of $prot in @all_pegs


    for ($pegI = 0; ($pegI < @all_pegs) && ($prot ne $all_pegs[$pegI]); $pegI++) {}
    if ($pegI == @all_pegs)
    {
        $pegI = 0;
    }

#   print STDERR "pegi=$pegI prot=$prot $all_pegs[$pegI]\n";

   return ( $gg, \@all_pegs, $pegI );
}


sub add_change_sim_threshhold_form
{
    my( $cgi, $html, $prot, $pinned_to ) = @_;

    my $user          = $cgi->param('user');
    my $new_framework = $cgi->param('new_framework') ? 1 : 0;
    my $SproutValue   = $cgi->param('SPROUT')        ? 1 : "";
    my $max           = $cgi->param('maxpin') || 300;

    my @change_sim_threshhold_form = ();
    push( @change_sim_threshhold_form, $cgi->start_form(-action => &FIG::cgi_url . "/chromosomal_clusters.cgi"));
    push( @change_sim_threshhold_form, $cgi->hidden(-name => "user", -value => $user)) if $user;
    push( @change_sim_threshhold_form, $cgi->hidden(-name => "maxpin",        -value => $max));
    push( @change_sim_threshhold_form, $cgi->hidden(-name => "prot",          -value => $prot));
    push( @change_sim_threshhold_form, $cgi->hidden(-name => "pinned_to",     -value => [@$pinned_to]));
    push( @change_sim_threshhold_form, $cgi->hidden(-name => "SPROUT",        -value => $SproutValue))   if $SproutValue;
    push( @change_sim_threshhold_form, $cgi->hidden(-name => 'new_framework', -value => $new_framework)) if $new_framework;
    push( @change_sim_threshhold_form, "Similarity Threshold: ", $cgi->textfield(-name => 'sim_cutoff', -size => 10, -value => 1.0e-20));
    push( @change_sim_threshhold_form, $cgi->submit('compute at given similarity threshhold'));
    push( @change_sim_threshhold_form, $cgi->end_form);

    push( @$html, @change_sim_threshhold_form);
    return;
}


#  I now attempt to document, clean code, and make orphan genes gray.  Wish us all luck. -- GJO

sub form_sets_and_set_color_and_text {
    my( $fig, $cgi, $gg, $pegI, $all_pegs, $sim_cutoff ) = @_;

    #  @$gg       is GenoGraphics objects (maps exist, but they will be modified)
    #  $pegI      is index of the reference protein in @$all_pegs
    #  @$all_pegs is a list of all proteins on the diagram

    #  all of the PEGs are now stashed in $all_pegs.  We are going to now look up similarities
    #  between them and form connections.  The tricky part is that we are going to use "raw" sims,
    #  which means that we need to translate IDs; a single ID in a raw similarity may refer to multiple
    #  entries in $all_pegs.  $pos_of{$peg} is set to a list of positions (of essentially identical PEGs).

    # This object supports the is_deleted_fid method. For Sprout, it is a special version that allows
    # synonym groups as similarity targets.
    my $figShim = FidCheck->new($fig);

    my %peg2i;   #  map from id (in @$all_pegs) to index in @$all_pegs
    my %pos_of;  #  maps representative id to indexes in @$all_pegs, and original id to its index
    my @rep_ids; #  list of representative ids (product of all maps_to_id)

    my ( $i, $id_i, %counts );
    for ($i=0; ($i < @$all_pegs); $i++)
    {
        $id_i = $all_pegs->[$i];
        $peg2i{ $id_i } = $i;

        my $rep = $fig->maps_to_id( $id_i );
        defined( $pos_of{ $rep } ) or push @rep_ids, $rep;
        $counts{$rep}++;
        push @{ $pos_of{ $rep } }, $i;
        if ( $rep ne $id_i )
        {
            push @{ $pos_of{ $id_i } }, $i;
        }
    }

    # print STDERR Dumper(\%pos_of, \%peg2i, \@rep_ids);

    #  @{$conn{ $rep }} will list all connections of a representative id
    #  (this used to be for every protein, not the representatives).

    my %conn;

    my @texts  = $cgi->param('text');   # map of id to text
    my @colors = $cgi->param('color');  # peg:color pairs
    my @color_sets = ();

    #  Case 1, find sets of related sequences using sims:

    if ( @colors == 0 )
    {
        #  Get sequence similarities among representatives
        my ( $rep, $id2 );
        foreach $rep ( @rep_ids )
        {
            #  We get $sim_cutoff as a global var (ouch)
            Trace("Seeking sims for $rep.") if T(4);
            my $sims = FIGRules::GetNetworkSims($figShim, $rep, {}, 500, $sim_cutoff, "raw");
            # Only proceed if there was no error.
            if (defined($sims)) {
                $conn{ $rep } = [ map { defined( $pos_of{ $id2 = $_->id2 } ) ? $id2 : () } @$sims ];
            }
            Trace("$rep has " . scalar(@{$conn{$rep}}) . " similarities.") if T(4);
        }
        # print STDERR &Dumper(\%conn);

        #  Build similarity clusters

        my %seen = ();
        foreach $rep ( @rep_ids )
        {
            next if $seen{ $rep };

            my @cluster = ( $rep );
            my @pending = ( $rep );
            $seen{ $rep } = 1;

            while ( $id2 = shift @pending )
            {
                my $k;
                foreach $k ( @{ $conn{ $id2 } } )
                {
                    next if $seen{ $k };

                    push @cluster, $k;
                    push @pending, $k;
                    $seen{ $k } = 1;
                }

            }
            if ((@cluster > 1) || ($counts{$cluster[0]} > 1))
            {
                push @color_sets, \@cluster;
            }
        }

        #  Clusters were built by representatives.
        #  Map (and expand) back to lists of indices into @all_pegs.

        @color_sets = map { [ map { @{ $pos_of{ $_ } } } @$_ ] }
                      @color_sets;
    }
    else  #  Case 2, supplied colors are group labels that should be same color
    {
        my( %sets, $peg, $x, $color );
        foreach $x ( @colors )
        {
            ( $peg, $color ) = $x =~ /^(.*):([^:]*)$/;
            if ( $peg2i{ $peg } )
            {
                push @{ $sets{ $color } }, $peg2i{ $peg };
            }
        }

        @color_sets = map { $sets{ $_ } } keys %sets;
    }

    #  Order the clusters from largest to smallest

    @color_sets = sort { @$b <=> @$a } @color_sets;
    # foreach ( @color_sets ) { print STDERR "[ ", join( ", ", @$_ ), " ]\n" }

    #  Move cluster with reference prot to the beginning:

    my $set1;
    @color_sets = map { ( &in( $pegI, $_ ) &&  ( $set1 = $_ ) ) ? () : $_ } @color_sets;
    if ( $set1 )
    {
        unshift @color_sets, $set1;
#       print STDERR &Dumper(["color_sets",[map { [ map { $all_pegs->[$_] } @$_ ] } @color_sets]]); die "aborted";
    }
#   else
#   {
#       print STDERR &Dumper(\@color_sets);
#       print STDERR "could not find initial PEG in color sets\n";
#   }

    my( %color, %text, $j );
    for ( $i=0; ($i < @color_sets); $i++)
    {
        my $color_set_i = $color_sets[ $i ];
        my $picked_color = &pick_color( $cgi, $all_pegs, $color_set_i, $i, \@colors );
        my $picked_text  = &pick_text(  $cgi, $all_pegs, $color_set_i, $i, \@texts );

        foreach $j ( @$color_set_i )
        {
            $color{$all_pegs->[$j]} = $picked_color;
            $text{$all_pegs->[$j]}  = $picked_text;
        }
    }

#   print STDERR &Dumper($all_pegs,\@color_sets);
    return (\%color,\%text);
}

sub add_commentary_form
{
    my( $cgi, $user, $html, $prot, $vals ) = @_;

    my $SproutValue   = $cgi->param('SPROUT')        ? 1 : "";
    my $new_framework = $cgi->param('new_framework') ? 1 : 0;

    my @commentary_form = ();
    my $ctarget = "window$$";

    my $uni = $cgi->param('uni');
    if (! defined($uni)) { $uni = "" }

    push( @commentary_form, $cgi->start_form(-target => $ctarget,
                                             -action => &FIG::cgi_url . "/chromosomal_clusters.cgi"
                                            ));
    push(@commentary_form, $cgi->hidden(-name => "request",       -value => "show_commentary"));
    push(@commentary_form, $cgi->hidden(-name => "new_framework", -value => $new_framework)) if $new_framework;
    push(@commentary_form, $cgi->hidden(-name => "prot",          -value => $prot));
    push(@commentary_form, $cgi->hidden(-name => "user",          -value => $user)) if $user;
    push(@commentary_form, $cgi->hidden(-name => "uni",           -value => $uni));
    push(@commentary_form, $cgi->hidden(-name => "SPROUT",        -value => $SproutValue)) if $SproutValue;
    push(@commentary_form, $cgi->hidden(-name => "show",          -value => [@$vals]));
    push(@commentary_form, $cgi->submit('commentary'));
    push(@commentary_form, $cgi->end_form());
    push(@$html,@commentary_form);

    return;
}


sub update_gg_with_color_and_text {
    my( $cgi, $gg, $color, $text, $prot ) = @_;

    my( $gene, $n, %how_many, $x, $map, $i, %got_color );

    my %must_have_color;

    # Here we get a list of the proteins we must have in order to be part of the result.
    # One of them will always be the focus protein. A gene that does not have a connection to
    # all the proteins in the must-have list will be discarded.
    my @must_have = $cgi->param('must_have');
    push @must_have, $prot;

    my @vals = ();
    for ( $i = (@$gg - 1); ($i >= 0); $i--)
    {
        my @vals1 = ();
        $map = $gg->[$i];  # @$map = ( abbrev, min_coord, max_coord, \@genes )

        undef %got_color;
        my $got_red = 0;
        my $found = 0;
        undef %how_many;

        foreach $gene ( @{$map->[3]} )
        {
            #  @$gene = ( min_coord, max_coord, symbol, color, text, id_link, pop_up_info )

            my $id = $gene->[5];
            if ( $x = $color->{ $id } )
            {
                $gene->[3] = $x;
                $gene->[4] = $n = $text->{ $id };
                $got_color{ $x } = 1;
                if ( ( $x =~ /^(red|color0)$/ )
                  && &FIG::between( $gene->[0], ($map->[1]+$map->[2])/2, $gene->[1] )
                    ) { $got_red = 1 }
                $how_many{ $n }++;
                my $org = $map->[0];
                $org = $org->[0] if ref($org);
                push @vals1, join( "@", $n, $i, $id, $org, $how_many{$n} );
                $found++;
            }
            else
            {
                $gene->[3] = "ltgray";  # Light gray
            }
            $gene->[5] = &HTML::fid_link( $cgi, $id, 0, 1 );
        }

        for ( $x = 0; ( $x < @must_have ) && $got_color{ $color->{ $must_have[ $x ] } }; $x++ ) {}
        if ( ( $x < @must_have ) || ( ! $got_red ) )
        {
#           print STDERR &Dumper($map);

            if ( @{ $map->[3] } > 0 ) {
                splice( @$gg, $i, 1 )
            }
        }
        else
        {
            push @vals, @vals1;
        }
    }
#   print STDERR &Dumper($gg);
    return \@vals;
}

sub thin_out_over_max {
    my( $cgi, $html, $prot, $gg, $in_pin ) = @_;

    my $user = $cgi->param('user')   || '';
    my $max  = $cgi->param('maxpin') || 300;

    if ($in_pin > $max)
    {
        my $sim_cutoff = $cgi->param('sim_cutoff');
        if (! $sim_cutoff) { $sim_cutoff = 1.0e-20 }

        my $to = &FIG::min(scalar @$gg,$max);
        my $new_framework = $cgi->param('new_framework') ? 1 : 0;
        push(@$html,$cgi->h1("Truncating from $in_pin pins to $to pins"),
                    $cgi->start_form(-action => &FIG::cgi_url . "/chromosomal_clusters.cgi"),,
                    "Max Pins: ", $cgi->textfield(-name => 'maxpin',
                                                  -value => $_,
                                                  -override => 1),
                    $cgi->hidden(-name => 'user', -value => $user),
                    $cgi->hidden(-name => "new_framework", -value => $new_framework),
                    $cgi->hidden(-name => 'prot', -value => $prot),
                    $cgi->hidden(-name => 'sim_cutoff', -value => $sim_cutoff),
                    $cgi->submit("Recompute after adjusting Max Pins"),
                    $cgi->end_form,
                    $cgi->hr);

        if (@$gg > $max)
        {
            my($i,$to_cut);
            for ($i=0; ($i < @$gg) && (! &in_map($prot,$gg->[$i])); $i++) {}

            if ($i < @$gg)
            {
                my $beg = $i - int($max/2);
                my $end = $i + int($max/2);
                if (($beg < 0) && ($end < @$gg))
                {
                    $beg = 0;
                    $end = $beg + ($max - 1);
                }
                elsif (($end >= @$gg) && ($beg > 0))
                {
                    $end = @$gg - 1;
                    $beg = $end - ($max - 1);
                }

                if ($end < (@$gg - 1))
                {
                    splice(@$gg,$end+1);
                }

                if ($beg > 0)
                {
                    splice(@$gg,0,$beg);
                }
            }
        }
    }
}

sub in_map {
    my($peg,$map) = @_;
    my $i;

    my $genes = $map->[3];
    for ($i=0; ($i < @$genes) && (index($genes->[$i]->[5],"$peg\&") < 0); $i++) {}
    return ($i < @$genes);
}

sub limit_pinned {
    my($prot,$pinned_to,$max) = @_;

    my($i,$to_cut);
    for ($i=0; ($i < @$pinned_to) && ($pinned_to->[$i] ne $prot); $i++) {}

    if ($i < @$pinned_to)
    {
        my $beg = $i - int($max/2);
        my $end = $i + int($max/2);
        if (($beg < 0) && ($end < @$pinned_to))
        {
            $beg = 0;
            $end = $beg + ($max - 1);
        }
        elsif (($end >= @$pinned_to) && ($beg > 0))
        {
            $end = @$pinned_to - 1;
            $beg = $end - ($max - 1);
        }

        if ($end < (@$pinned_to - 1))
        {
            splice(@$pinned_to,$end+1);
        }

        if ($beg > 0)
        {
            splice(@$pinned_to,0,$beg);
        }
    }
    return @$pinned_to;
}

sub resolve_id {
    my($fig,$id) = @_;
    my(@pegs);

    if ($id =~ /^fig/)              { return $id }

    if (@pegs = $fig->by_alias($id)) { return @pegs }

    if (($id =~ /^[A-Z0-9]{6}$/) && (@pegs = $fig->by_alias("uni|$id")))   { return @pegs }

    if (($id =~ /^\d+$/) && (@pegs = $fig->by_alias("gi|$id")))            { return @pegs }

    if (($id =~ /^\d+$/) && (@pegs = $fig->by_alias("gi|$id")))            { return @pegs }

    return ();
}

sub cache_html {
    my($fig,$cgi,$html) = @_;

    my @params = sort $cgi->param;
#   print STDERR &Dumper(\@params);
    if ((@params == 3) &&
        ($params[0] eq 'prot') &&
        ($params[1] eq 'uni') &&
        ($params[2] eq 'user'))
    {
        my $prot = $cgi->param('prot');
        if ($prot =~ /^fig\|\d+\.\d+\.peg\.\d+$/)
        {
            my $user = $cgi->param('user');
            my $uni  = $cgi->param('uni');
            my $file = &cache_file($prot,$uni);
            Trace("Cache file is $file for prot=$prot;uni=$uni;user=$user.") if T(3);
            if (open(CACHE,">$file"))
            {
                Trace("Writing to cache file.") if T(3);
                foreach $_ (@$html)
                {
#                   $_ =~ s/user=$user/USER=@@@/g;
                    print CACHE $_;
                }
                close(CACHE);
            }
        }
    }
}

sub cache_file {
    my($prot,$uni, $sim_cutoff) = @_;

    &FIG::verify_dir("$FIG_Config::temp/Cache");
    return "$FIG_Config::temp/Cache/$prot:$uni:$sim_cutoff";
}

#
# Determine if we have a locally cached copy of the output for these
# parameters.
#
sub handled_by_local_cache
{
    my($fig, $cgi, $prot, $sim_cutoff) = @_;

    my @params = sort $cgi->param;

    #
    # Determine if the parameters list contains only prot/uni/user/SPROUT.
    #

    my $i;
    for ($i=0; ($params[$i] =~ /prot|uni|user|SPROUT/); $i++) {}

#    warn "handled_by_cache: i=$i params=@params\n";
    if ($i != @params)
    {
        return;
    }

    my $sprout = $cgi->param('SPROUT') ? "&SPROUT=1" : "";
    my $user = $cgi->param('user');
    my $uni  = $cgi->param('uni');
    my $file = &cache_file($prot,$uni, $sim_cutoff);

    if (!open(CACHE,"<$file"))
    {
        #
        # No local cache.
        #
        Trace("No local cache found for prot=$prot;uni=$uni;sim_cutoff=$sim_cutoff.") if T(3);
        return ;
    }

    warn "Using local cache $file\n";
    my $html = [];
    my $fig_loc;
    my $to_loc = &FIG::cgi_url;
    $to_loc =~ /http:\/\/(.*?)\/FIG/;
    $to_loc = $1;
    while (defined($_ = <CACHE>))
    {
        if ((! $fig_loc) && ($_ =~ /http:\/\/(.*?)\/FIG\/chromosomal_clusters.cgi/))
        {
            $fig_loc = quotemeta $1;
        }

        $_ =~ s/http:\/\/$fig_loc\//http:\/\/$to_loc\//g;
        $_ =~ s/USER=\@\@\@/user=$user$sprout/g;
        $_ =~ s/\buser=[^&;\"]*/user=$user$sprout/g;

        push(@$html,$_);
    }
    close(CACHE);

    my $SproutValue = $cgi->param('SPROUT') ? "1" : "";
    my_show_page($SproutValue, $cgi,$html);
    return 1;
}


sub handled_by_precomputed_pin
{
    my($fig, $cgi, $html, $prot, $sim_cutoff) = @_;
    my $res;

    # This next part is SEED only!
    if ($fig->get_system_name() eq 'seed')
    {
        #tick('top of handle');

        #
        # Look up in the database to see if we have this locally.
        #

        my $db_handle = $fig->db_handle();

        #  When the tables do not exist, the behavior of DBKernel::SQL() is very
        #  unfriendly. Check for the tables first -- GJO
        my @tables = $db_handle ? grep { m/^file_table$/i || m/^pin_seeks$/i } $db_handle->get_tables()
                                : ();

        if ( @tables == 2 )
        {
            my $dbh = $db_handle->{_dbh};
            local $dbh->{PrintError} = 0;
            local $dbh->{RaiseError} = 1;
            #  DBKernel::SQL() calls Confess, so we got many stack dumps when
            #  the tables do not exist.
            eval {
                #  Simplify the cutoff match calculation by moving multiply out of the SQL -- GJO
                $res = $db_handle->SQL(qq(SELECT t.file, t.fileno, p.seek, p.len
                                          FROM  file_table t, pin_seeks p
                                          WHERE (abs(p.cutoff - ?) < ? AND
                                                 fid = ? AND t.fileno = p.fileno
                                                )
                                         ), undef, $sim_cutoff, 1e-5*$sim_cutoff, $prot);
            };
            if ($@)
            {
                warn "pin_seek lookup failed: $@\n";
                system("$FIG_Config::bin/index_pins");
                $res = undef;
            }
        }
    }

    if (not $res or @$res == 0)
    {
        #
        # See if we can pull it down from clearinghouse.
        #

        $res = download_and_install_precomputed_pin($fig, $cgi, $prot, $sim_cutoff);
        if (! defined($res)) {
            # Download failed.
            return 0;
        }
    }

    # warn "found precomputed pin for $prot\n";
    my $pin_perl;
    if (ref $res eq 'ARRAY') {
        # Here the precomputed pin is in a file.
        my($file, $fileno, $seek, $len) = @{$res->[0]};

        if (!defined($fileno))
        {
            warn "No pin for $prot\n";
            return 0;
        }

        if ($file !~ m,^/,)
        {
            $file = "$FIG_Config::fig_disk/$file";
        }

        my $fh   = $fig->openF( $file );
        $fh or confess "could not open pins for $file: $!\n";

        seek($fh, $seek, 0) or die "Cannot seek to $seek in $file: $!\n";
        read($fh, $pin_perl, $len) or die "Cannot read pin from $file: $!\n";
    } else {
        # Here we have the precomputed pin directly.
        $pin_perl = $res;
    }
    my $gg;
    {
        my $VAR1;
        $gg = eval $pin_perl;
    }

    #tick('after eval perl');

    #
    # Walk the genographics data, making the fids be links to this SEED, and fill in the popup
    # info with the current local data.
    #

    my $i = 0;
    my $vals = [];
    my $ngg = [];
    for my $map (@$gg)
    {
        my @glist = @{$map->[3]};

        #
        # Extract the list of fids we are going to be mapping.
        #
        my @fids = map { $_->[5] } @glist;
        @fids = grep { not $fig->is_deleted_fid($_) } @fids;

        #
        # Extract info for the popup
        #

        my $first_fid = $fids[0];
        my $genome = $fig->genome_of($first_fid);

        if ($fig->is_genome($genome))
        {
            push(@$ngg, $map);
        }
        else
        {
            next;
        }
        my $org = $fig->org_of($first_fid);

        my $contig = $fig->contig_of($fig->feature_location($first_fid));
        my $desc = "Genome: $org ($genome)<br />Contig: $contig";

        #
        # Do the database lookups in bulk.
        #

        my $funs = $fig->function_of_bulk(\@fids, 1);
        my $aliases = $fig->uniprot_aliases_bulk(\@fids, 1);

        #
        # Patch old data to have the new tuple as the first item
        # to allow genographics to create popups.
        #

        my $abbrev = &FIG::abbrev($org);
        $map->[0] = [$abbrev, undef, $desc, undef, 'Contig'];

        my %how_many;

        for my $gene (@glist)
        {
            my $fid = $gene->[5];
            $gene->[5] = &HTML::fid_link( $cgi, $fid, 0, 1 );

            #
            # Recover vals array for the commentary.
            #
            if ($gene->[3] ne "ltgray")
            {
                my $n = $gene->[4];
                $how_many{$n}++;
                push(@$vals, join("@", $n, $i, $fid, $abbrev, $how_many{$n}));
            }

            my($function, $aliases1, $uniprot, $info);

            # Build the pop-up information for the gene:

#           $function = $fig->function_of($fid);
            $function = $funs->{$fid};

            #$aliases1 = $fig->feature_aliases($fid);
            #( $uniprot ) = $aliases1 =~ /(uni\|[^,]+)/;

            my $alist = $aliases->{$fid};
            if ($alist)
            {
                $uniprot = join(" ", @$alist);
            }

            $info  = join( '<br/>', "<b>Org:</b> $org",
                             "<b>PEG:</b> $fid",
#                            "<b>Contig:</b> $contig1",
#                            "<b>Begin:</b> $beg1",
#                            "<b>End:</b> $end1",
                             ( $function ? "<b>Function:</b> $function" : () ),
                             ( $uniprot ? "<b>Uniprot ID:</b> $uniprot" : () )
                            );

            if (0)
            {
                my @allattributes=$fig->get_attributes($fid);
                foreach my $eachattr (@allattributes) {
                    my ($gotpeg,$gottag,$val, $url) = @$eachattr;
                    $info .= "<br/><b>Attribute:</b> $gottag $val $url";
                }
            }
            $gene->[6] = $info;

        }
        $i++;
    }
    $gg = $ngg;

    #tick("after loop");

    add_change_sim_threshhold_form( $cgi, $html, $prot, [] );

    push( @$html, @{ &GenoGraphics::render( $gg, 1000, 4, 1 ) } );

    #tick("after render");

    push( @$html,    &FIGGenDB::linkClusterGenDB($prot) );

    #tick("after link");

    #&cache_html($fig,$cgi,$html);

    &add_commentary_form( $cgi, $user, $html, $prot, $vals );

    my $SproutValue = $cgi->param('SPROUT') ? "1" : "";
    my_show_page( $SproutValue, $cgi, $html );

    #tick("after show");

    return 1;
}


sub download_and_install_precomputed_pin
{
    my($fig, $cgi, $prot, $sim_cutoff) = @_;

    my $ua = new LWP::UserAgent;

    my $peg_enc = uri_escape($prot);

    my $pins_url = "$FIG_Config::pin_server_url";

    $pins_url = "http://anno-2.nmpdr.org/simserver/FIG/precomputed_pin.cgi"
        unless $pins_url ne '';


    my $url = "$pins_url?peg=$peg_enc&cutoff=$sim_cutoff";
    my $resp = $ua->get($url);

    if ($resp->is_success)
    {
        my $pin = $resp->content;

        if ($pin =~ /NOT FOUND/)
        {
            Trace("Pins for $prot not found at $url.") if T(3);
            return undef;
        }

        #
        # Write the pin to local pin cache if this is the SEED.
        #
        # RDO 2006/0731 - don't do this, it gets in the way
        # of readonly SEED systems, and probably isn't critical.
        #
        # If we want it back we should architect a better mechanism
        #
        if (0 and $fig->get_system_name eq 'seed') {
            my $pin_dir = "$FIG_Config::data/PrecomputedPins";

            my $genome = &FIG::genome_of($prot);
            my $pgdir = "$pin_dir/$genome";
            &FIG::verify_dir($pgdir);
            warn "pgdir=$pgdir\n";
            my $pfile = "$pgdir/cache";

            open(PIN, ">>$pfile") or die "Cannot open $pfile: $!\n";
            flock(PIN, LOCK_EX);
            seek(PIN, 0, 2);

            print PIN "$prot\n";
            print PIN "cutoff\t$sim_cutoff\n";
            print PIN "downloaded_from\t$url\n";
            print PIN "download_time\t" . time . "\n";
            print PIN "//\n";
            my $start = tell(PIN);
            print PIN "$pin\n";
            my $end = tell(PIN);
            print PIN "//\n";

            close(PIN);

            my $len = $end - $start;

            warn "Inserted, start=$start end=$end len=$len\n";

            my $fnum = $fig->file2N($pfile);
            $fig->db_handle()->SQL(qq(INSERT INTO pin_seeks (fid, cutoff, fileno, seek, len)
                                      VALUES (?, ?, ?, ?, ?)), undef,
                                   $prot, $sim_cutoff, $fnum, $start, $len);

            return [[$pfile, $fnum, $start, $len]];
        } else {
            # If this is not SEED, return the raw PIN.
            return $pin;
        }
    }
    else
    {
        return undef;
    }

}

sub handled_by_clearinghouse_image_cache
{
    my($fig, $cgi, $user, $prot, $sim_cutoff) = @_;
    my $to_loc = &FIG::cgi_url;
    my $h = get_clearinghouse_image_cache($fig, $prot, $sim_cutoff);

    if (not $h)
    {
        return 0;
    }

    my $SproutValue = $cgi->param('SPROUT') ? "1" : "";
    my $sprout = $SproutValue ? "&SPROUT=1" : "";

    #
    # If we're in sprout, strip the form at the end.
    # We need to also tack on a hidden variable that sets SPROUT=1.
    #

    my $html = [];

    for (split(/\n/, $h))
    {
        if ($SproutValue)
        {
            if(/form.*GENDB/)
            {
                last;
            }
            elsif (/type="submit" name=\"(commentary|compute)/)
            {
                push(@$html, qq(<input type="hidden" name="SPROUT" value="1">\n));
            }

            #
            # Don't offer the recompute option.
            #

            s,Similarity Threshold:.*value="compute at given similarity threshhold" />,,;

        }
        s/user=master:cached/user=$user$sprout/g;
        s/name="user" value="master:cached"/name="user" value="$user"/;
        push(@$html, "$_\n");
    }

    my_show_page($SproutValue, $cgi, $html);
    return 1;
}


sub get_pin {
    my($fig,$peg) = @_;

    my($peg2,%pinned_to,$tuple);

    if ($fig->table_exists('pchs') &&
        $fig->is_complete($fig->genome_of($peg)))
    {
        foreach $peg2 (map { $_->[0] } $fig->coupled_to($peg))
        {
            foreach $tuple ($fig->coupling_evidence($peg,$peg2))
            {
                $pinned_to{$tuple->[0]} = 1;
            }
        }
        my @tmp = $fig->sort_fids_by_taxonomy(keys(%pinned_to));
        if (@tmp > 0)
        {
            return @tmp;
        }
    }
    return $fig->sort_fids_by_taxonomy($fig->in_pch_pin_with($peg));
}

sub get_clearinghouse_image_cache
{
    my($fig, $peg, $sim_cutoff) = @_;

    my $ua = new LWP::UserAgent;

    my $peg_enc = uri_escape($peg);
    my $my_url_enc = uri_escape($fig->cgi_url());
    my $pins_url = "http://clearinghouse.theseed.org/Clearinghouse/pins_for_peg.cgi";

    if ($FIG_Config::pin_server_url ne '')
    {
        $pins_url = $FIG_Config::pin_server_url;
    }

    my $url = "$pins_url?peg=$peg_enc&fig_base=$my_url_enc&cutoff=$sim_cutoff";
    my $resp = $ua->get($url);

    if ($resp->is_success)
    {
        return $resp->content;
    }
    else
    {
        return undef;
    }
}

sub my_show_page
{
    my($sprout, $cgi, $html) = @_;

    if ($sprout)
    {
        my $loc_url = $cgi->url(-absolute => 1, -full => 1, -query => 1, -path_info => 1);

        #
        # Truncate it in case the url is humongous (like it will be for the pins commentary page).
        #

        $loc_url = substr($loc_url, 0, 100);

        my $h = {
            location_tag => [uri_escape($loc_url)],
            pins => $html
            };
        print "Content-Type: text/html\n\n";

        my $templ;
        if ($FIG_Config::template_url) {
            $templ = "$FIG_Config::template_url/CCluster_tmpl.php";
        } else {
            $templ = "<<$FIG_Config::fig/CGI/Html/CCluster_tmpl.html";
        }
        print PageBuilder::Build($templ, $h,"Html");
    }
    else
    {
        &HTML::show_page($cgi, $html);
    }
}

sub ff_link {
    my($fam) = @_;

    if (! $fam) { return "" }
    my $url = &FIG::cgi_url . "/chromosomal_clusters.cgi?request=figfam&fam=$fam";
    return "<a href=$url>$fam</a>";
}

sub evidence_codes_link {
    my($cgi) = $_;

    return "<A href=\"Html/evidence_codes.html\" target=\"SEED_or_SPROUT_help\">Ev</A>";
}

sub evidence_codes {
    my($fig,$peg,$codes) = @_;

    if ($peg !~ /^fig\|\d+\.\d+\.peg\.\d+$/) { return "" }
    if (! defined $codes) {
        Trace("No codes found for $peg.") if T(3);
    } elsif (ref $codes ne 'ARRAY') {
        Trace("Invalid code array for $peg.") if T(3);
    } else {
        Trace("Processing evidence codes for $peg. " . scalar(@{$codes}) . " codes in list.") if T(3);
    }
    my @pretty_codes = ();
    foreach my $code (@{$codes}) {
        my $pretty_code = $code->[2];
        my ($cd, $ss);
        if ($pretty_code =~ /;/) {
            ($cd, $ss) = split(";", $code->[2]);
            $ss =~ s/_/ /g;
            $pretty_code = $cd . " in " . $ss;
        }
        push(@pretty_codes, $cd);
    }
    return @pretty_codes;
}



#####################################################################
