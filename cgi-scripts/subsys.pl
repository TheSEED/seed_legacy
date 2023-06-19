# -*- perl -*-
#
# Copyright (c) 2003-2006 University of Chicago and Fellowship
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

use FIG;
use FIGjs;  # mouseover()
use GD;
use MIME::Base64;
use KGMLData; # to parse relations in KEGG maps

our $fig = new FIG;

use Subsystem;

use URI::Escape;  # uri_escape()
use HTML;
use strict;
use tree_utilities;

use raelib;
our $raelib=new raelib; #this is for the excel workbook stuff.

use CGI;
use CGI::Carp qw(fatalsToBrowser); # this makes debugging a lot easier by throwing errors out to the browser

our $cgi = new CGI;

$ENV{"PATH"} = "$FIG_Config::bin:$FIG_Config::ext_bin:" . $ENV{"PATH"};

if (0)
{
    my $VAR1;
    eval(join("",`cat /tmp/ssa_parms`));
    $cgi = $VAR1;
#   print STDERR &Dumper($cgi);
}

if (0)
{
    print $cgi->header;
    my @params = $cgi->param;
    print "<pre>\n";
    foreach $_ (@params)
    {
        print "$_\t:",join(",",$cgi->param($_)),":\n";
    }

    if (0)
    {
        if (open(TMP,">/tmp/ssa_parms"))
        {
            print TMP &Dumper($cgi);
            close(TMP);
        }
    }
    exit;
}

# request to display the phylogenetic tree
#
my $request = $cgi->param("request");
if ($request && ($request eq "show_tree"))
{
    print $cgi->header;
    &show_tree;
    exit;
}

# Some timing code that can be deleted:  ## time ##
my $time_it = 0;                         ## time ##
my @times;                               ## time ##
push @times, scalar time() if $time_it;  ## time ##

my $html = [];
push @$html, ( $cgi->param('ssa_name') ? "<TITLE>SEED Subsystem: " . $cgi->param('ssa_name') . "</TITLE>\n"
                                       : "<TITLE>SEED Subsystems</TITLE>\n"
             ); # RAE: every page deserves a title

my $user = $cgi->param('user'); 
if (($user =~ /^\S/) && ($user !~ /^master:/)) { $user = "master:$user" }

$fig->set_user($user);

if ($cgi->param('resynch_peg_connections') && (my $ssa = $cgi->param('ssa_name')))
{
    $ssa =~ s/ /_/g;
    my $subsystem = new Subsystem($ssa,$fig,0);
    $subsystem->db_sync(0);
    undef $subsystem;
    &one_cycle($fig,$cgi,$html);
}
elsif ($user && ($cgi->param("extend_with_billogix")))
{
    #
    # Start a bg task to extend the subsystem.
    #

    my $ssa = $cgi->param('ssa_name');

    my $sub = $fig->get_subsystem($ssa);

    if ($sub && ($user eq $sub->get_curator))
    {
        #
        # See if there's already an extend job running.
        #
            
        my $curpid = $sub->get_current_extend_pid();
        if ($curpid)
        {
            warn "Found current pid $curpid\n";
            my $j = $fig->get_job($curpid);
            warn "job is $j\n";
            warn "running is ", $j->running(), "\n" if $j;
            if ($j && $j->running())
            {
                push(@$html, "Subsystem extension is already running as job number $curpid. <br>",
                     "Click <a href=\"seed_ctl.cgi?user=$user\">here</a> to see currently running jobs and their status");
                last;
            }
        }
        
        my $pid = $fig->run_in_background(sub {$sub->extend_with_billogix($user);});
            
        push(@$html,
             "Subsystem extension started as background job number $pid <br>\n",
             "Click <a href=\"seed_ctl.cgi?user=$user\">here</a> to see currently running jobs and their status");
            
        $sub->set_current_extend_pid($pid);
    }
    else
    {
        push(@$html, "Subsystem '$ssa' could not be loaded");
    }
    &HTML::show_page($cgi, $html);
    exit;
}
elsif ($cgi->param('lock annotations') && ($user = $cgi->param('user')))
{
    my @orgs = $cgi->param('genome_to_lock');
    @orgs = map { $_ =~ /^(\d+\.\d+)/; $1 } @orgs;
    my @roles = $cgi->param('roles_to_lock');
    my $ssa = $cgi->param('ssa_name');
    $ssa =~ s/ /_/g;
    push(@$html,"<br>");

    foreach my $genome (@orgs)
    {
	foreach my $role (@roles)
	{
	    foreach my $peg ($fig->pegs_in_subsystem_cell($ssa,$genome,$role))
	    {
		$user =~ s/master://;
		$fig->lock_fid($user,$peg);
		push(@$html,"locked $peg<br>\n");
	    }
	}
    }
    &HTML::show_page($cgi, $html);
    exit;
}
elsif ($cgi->param('unlock annotations') && ($user = $cgi->param('user')))
{
    my @orgs = $cgi->param('genome_to_lock');
    @orgs = map { $_ =~ /^(\d+\.\d+)/; $1 } @orgs;
    my @roles = $cgi->param('roles_to_lock');
    my $ssa = $cgi->param('ssa_name');
    $ssa =~ s/ /_/g;

    push(@$html,"<br>");

    foreach my $genome (@orgs)
    {
	foreach my $role (@roles)
	{
	    foreach my $peg ($fig->pegs_in_subsystem_cell($ssa,$genome,$role))
	    {
		$user =~ s/master://;
		$fig->unlock_fid($user,$peg);
		push(@$html,"unlocked $peg<br>\n");
	    }
	}
    }
    &HTML::show_page($cgi, $html);
    exit;
}
else
{
    $request = defined($request) ? $request : "";
    
    if    (($request eq "reset") && $user)
    {
        &reset_ssa($fig,$cgi,$html);        # allow user to go back to a previous version of the ss
    }
    elsif    (($request eq "reset_to") && $user)
    {
        &reset_ssa_to($fig,$cgi,$html);     # this actually resets to the previous version
        &one_cycle($fig,$cgi,$html);
    }
    elsif    (($request eq "make_exchangable") && $user)
    {
        &make_exchangable($fig,$cgi,$html);
        &show_initial($fig,$cgi,$html);
    }
    elsif    (($request eq "make_unexchangable") && $user)
    {
        &make_unexchangable($fig,$cgi,$html);
        &show_initial($fig,$cgi,$html);
    }
    elsif    ($request eq "show_ssa")
    {
	my $ssa = $cgi->param('ssa_name');
	$ssa =~ s/ /_/g;
	my $html1 = [];
	my $html2 = [];
        &one_cycle($fig,$cgi,$html2);

	if (-e "$FIG_Config::data/Subsystems/$ssa/warnings")
	{
	    my $ts = localtime($^T - ((-M "$FIG_Config::data/Subsystems/$ssa/warnings") * 24 * 60 * 60));
	    push(@$html1,$cgi->h1("Last check was at $ts"));

	    my @tmp = $fig->file_read("$FIG_Config::data/Subsystems/$ssa/warnings");
	    my @mismatches   = grep { ($_ =~ /mismatch\t(\S+)\t([^\t]+)/) && 
				      &still_in($fig,$1,$2,$ssa) 
				    } @tmp;
	    my $mismatchesN  = (@mismatches > 0) ? @mismatches : 0;
	    push(@$html1,$cgi->h2("$mismatchesN entries mismatch the role"));

	    my @left_out     = grep { ($_ =~ /left-out\t(\S+)\t([^\t]+)/) && 
				      &still_left_out($fig,$1,$2,$ssa) 
				    } @tmp;

	    my $left_outN    = (@left_out > 0) ? @left_out : 0;
	    push(@$html1,$cgi->h2("$left_outN entries should be added for existing genomes"));

	    my $sobj = $fig->get_subsystem($ssa);
	    my %genomes_in_sub = map { $_ => 1 } $sobj->get_genomes;
	    my @maybe_add    = grep { ($_ =~ /maybe-add\t[^\t]+\t[^\t]+\t(\d+\.\d+)/) && 
				      (! $genomes_in_sub{$1}) 
				    } @tmp;
	    my $maybe_addN   = (@maybe_add > 0) ? @maybe_add : 0;
	    push(@$html1,$cgi->h2("$maybe_addN genomes maybe should be added"));
	    my $esc_ssa = uri_escape($ssa);
	    if ($mismatchesN || $left_outN || $maybe_addN)
	    {
		push(@$html1,"<b>To see results of the last check:</b>&nbsp;",
		            $cgi->a({href => "check_subsys.cgi?user=$user&subsystem=$esc_ssa&request=check_ssa&fast=1",
				     target => 'check_window'
				    },
			            "click here")
		     );
	    }
	    push(@$html1,"<br>","If you wish to run a new check now: ",
                        $cgi->a({href => "check_subsys.cgi?user=$user&subsystem=$esc_ssa&request=check_ssa",
				 target => 'check_window'
				},
                                "click here<br>")
		 );

	    push(@$html1,"If you wish to run a summary for all of your subsystems: ",
                        $cgi->a({href => "check_subsys.cgi?user=$user&request=check_summary",
				 target => 'check_window'
				},
                                "click here<hr><br>")
		 );

	}
	push(@$html,@$html1,@$html2);
    }
    #
    # Note that this is a little different; I added another submit button
    # to the delete_or_export_ssa form, so have to distinguish between them
    # here based on $cgi->param('delete_export') - the original button,
    # or $cgi->param('publish') - the new one.
    #
    elsif (($request eq "delete_or_export_ssa") && $user &&
            defined($cgi->param('delete_export')))
    {
        my($ssa,$exported);
        $exported = 0;
        foreach $ssa ($cgi->param('export'))
        {
            if (! $exported)
            {
                print $cgi->header;
                print "<pre>\n";
            }
            &export($fig,$cgi,$ssa);
            $exported = 1;
        }

        foreach $ssa ($cgi->param('export_assignments'))
        {
            &export_assignments($fig,$cgi,$ssa);
        }

        foreach $ssa ($cgi->param('delete'))
        {
            my $sub = $fig->get_subsystem($ssa);
            $sub->delete_indices();

            my $cmd = "rm -rf '$FIG_Config::data/Subsystems/$ssa'";
            my $rc = system $cmd;
        }

        if (! $exported)
        {
            &show_initial($fig,$cgi,$html);
        }
        else
        {
            print "</pre>\n";
            exit;
        }
    }
    elsif (($request eq "delete_or_export_ssa") && $user &&
            defined($cgi->param('publish')))
    {
        my($ssa,$exported);
        my($ch) = $fig->get_clearinghouse();

        print $cgi->header;

        if (!defined($ch))
        {
            print "cannot publish: clearinghouse not available\n";
            exit;
        }

        foreach $ssa ($cgi->param('publish_to_clearinghouse'))
        {
            print "<h2>Publishing $ssa to clearinghouse...</h2>\n";
            $| = 1;
            print "<pre>\n";
            my $res = $fig->publish_subsystem_to_clearinghouse($ssa);
            print "</pre>\n";
            if ($res)
            {
                print "Published <i>$ssa </i> to clearinghouse<br>\n";
            }
            else
            {
                print "<b>Failed</b> to publish <i>$ssa</i> to clearinghouse<br>\n";
            }
        }
        exit;
    }
    elsif (($request eq "delete_or_export_ssa") && $user &&
            defined($cgi->param('reindex')))
    {

        my @ss=$cgi->param('index_subsystem');
        my $job = $fig->index_subsystems(@ss);
        push @$html, "<h2>ReIndexing these subsystems...</h2>\n<ul>", map {"<li>$_</li>"} @ss;
        push @$html, "</ul>\n<p>... is running in the background with job id $job. You may check it in the ",
             "<a href=\"seed_ctl.cgi?user=$user\">SEED Control Panel</a></p>\n";
        &show_initial($fig,$cgi,$html);
    }
    elsif (($request eq "delete_or_export_ssa") && $user &&
                defined($cgi->param('save_clicks')))
    {
        my @userss=$cgi->param("users_ss");
        my %nmpdrss=map {($_=>1)} $cgi->param("nmpdr_ss");
        my %distss=map {($_=>1)} $cgi->param("dist_ss");
	my %autoss=map {($_=>1)} $cgi->param("auto_update_ok");

        foreach my $ssa (@userss)
        {
            $nmpdrss{$ssa} ? $fig->nmpdr_subsystem($ssa, 1) : $fig->nmpdr_subsystem($ssa, -1);
            $distss{$ssa}  ? $fig->distributable_subsystem($ssa, 1) : $fig->distributable_subsystem($ssa, -1);
	    $autoss{$ssa}  ? $fig->ok_to_auto_update_subsys($ssa, 1) : $fig->ok_to_auto_update_subsys($ssa, -1);
        }
        &manage_subsystems($fig,$cgi,$html);
    }
    elsif ($user && ($request eq "new_ssa") && ($cgi->param('copy_from1')) && (! $cgi->param('cols_to_take1')))
    {
        my $name = $cgi->param('ssa_name');
        my $copy_from1 = $cgi->param('copy_from1');
        my $copy_from2 = $cgi->param('copy_from2');
        my(@roles1,@roles2);

        push(@$html,$cgi->start_form(-action => "subsys.cgi",
                    -method => 'post'),
                $cgi->hidden(-name => 'copy_from1', -value => $copy_from1, -override => 1),
                $cgi->hidden(-name => 'user', -value => $user, -override => 1),
                $cgi->hidden(-name => 'ssa_name', -value => $name, -override => 1),
                $cgi->hidden(-name => 'request', -value => 'new_ssa', -override => 1)
            );

        @roles1 = $fig->subsystem_to_roles($copy_from1);
        if (@roles1 > 0)
        {
            push(@$html,$cgi->h1("select columns to be taken from $copy_from1"),
                    $cgi->scrolling_list(-name => 'cols_to_take1',
                        -values => ['all',@roles1],
                        -size => 10,
                        -multiple => 1
                        ),
                    $cgi->hr
                );
        }

        if ($copy_from2)
        {
            @roles2 = $fig->subsystem_to_roles($copy_from2);
            if (@roles2 > 0)
            {
                push(@$html,$cgi->hidden(-name => 'copy_from2', -value => $copy_from2, -override => 1));
                push(@$html,$cgi->h1("select columns to be taken from $copy_from2"),
                        $cgi->scrolling_list(-name => 'cols_to_take2',
                            -values => ['all',@roles2],
                            -size => 10,
                            -multiple => 1
                            ),
                        $cgi->hr
                    );
            }
        }
        push(@$html,$cgi->submit('build new subsystem'),
                $cgi->end_form
            );
    }
    elsif ($user && ($request eq "new_ssa") && ($cgi->param('move_from')))
    {
        my $name = $cgi->param('ssa_name');
        $name=$fig->clean_spaces($name);
        $name=~s/ /_/g;
        my $move_from = $cgi->param('move_from');
        if (-d "$FIG_Config::data/Subsystems/$move_from" && !(-e "$FIG_Config::data/Subsystems/$name")) {
            my $res=`mv $FIG_Config::data/Subsystems/$move_from $FIG_Config::data/Subsystems/$name`;
            my $job = $fig->index_subsystems($name);
            push @$html, "<p>The subsystem <b>$move_from</b> was moved to <b>$name</b> and got the result $res. The new subsystem is being indexed with job id $job\n",
                 "(check the <a href=\"seed_ctl.cgi?user=$user\">SEED control panel</a> for more information</p>\n";
        } 
        elsif (-e "$FIG_Config::data/Subsystems/$name") 
        {
            push @$html, "<p>The subsystem <b>$move_from</b> was <b><i>NOT</i></b> moved because the subsystem $name already exists</p>";
        }
        else {
            push @$html, "<p>The subsystem <b>$move_from</b> was not found. Sorry</p>";
        }
        &show_initial($fig,$cgi,$html);
    }           
    elsif ($request eq "new_ssa")
    {
        &new_ssa($fig,$cgi,$html);
    }
   
#RAE: undelete these 5 commented out line for the new interface
    elsif ($request eq "manage_ss") 
#    else
    { 
        &manage_subsystems($fig,$cgi,$html);
    }
    else
    {
       # push @$html, $cgi->div({class=>"diagnostic"}, "Request: $request\n");
        &show_initial($fig,$cgi,$html);
    }
}

&HTML::show_page($cgi,$html);
exit;

sub still_left_out {
    my($fig,$peg,$func,$sub) = @_;

    if ($func ne $fig->function_of($peg))   { return 0 }
    my @subs = $fig->peg_to_subsystems($peg);
    my $i;
    for ($i=0; ($i < @subs) && ($sub ne $subs[$i]); $i++) {}
    return ($i == @subs);
}

sub still_in {
    my($fig,$peg,$func,$role,$sub) = @_;

    if ($func ne &stripped_function_of($fig,$peg))   { return 0 }
    $role =~ s/\s+$//;
    if ($func eq $role)                     { return 0 }

    my @subs = $fig->peg_to_subsystems($peg);
    my $i;
    for ($i=0; ($i < @subs) && ($sub ne $subs[$i]); $i++) {}
    return ($i < @subs);
}

sub stripped_function_of {
    my($fig,$peg) = @_;

    my $func = $fig->function_of($peg);
    $func =~ s/\s*\#.*$//;
    return $func;
}

sub show_initial {
    # a new first page written by Rob
    my($fig,$cgi,$html) = @_;

    # we get this information here and set things so that when we create the links later everything is already set.
    my $sort = $cgi->param('sortby');
    unless ($sort) {$sort="Classification"}
    my $show_clusters=$cgi->param('show_clusters');
    my $sort_ss=$cgi->param('sort');
    my $minus=$cgi->param('show_minus1');
    my $show_genomes=$cgi->param('showgenomecounts');
    
    
    # now set the values into $cgi so that we have them for later
    $cgi->param('sortby', $sort); # this is the table sort
    $cgi->param('show_clusters', $show_clusters); # whether or not to show the clusters
    $cgi->param('sort', $sort_ss); # this is the sort of the organisms in display
    $cgi->param('show_minus1', $minus); # whether to show -1 variants
    $cgi->param('showgenomecounts', $show_genomes); # whether to show genomes on the first page
    
    my @ssa = map {
     my $ss=$_;
     my ($version, $curator, $pedigree, $roles)=$fig->subsystem_info($ss->[0]);
     push @$ss, scalar(@$roles), $version;
     push @$ss, scalar(@{$fig->subsystem_genomes($ss->[0])}) if ($cgi->param('showgenomecounts'));
     $fig->subsystem_classification($ss->[0], [$cgi->param($ss->[0].".class1"), $cgi->param($ss->[0].".class2")]) if ($cgi->param($ss->[0].".class1"));
     unshift @$ss, @{$fig->subsystem_classification($ss->[0])};
     if ($ss->[3] eq $user) {$ss->[3] = [$ss->[3], "td style='background-color: #BA55D3'"]}
     $_=$ss;
    }
    &existing_subsystem_annotations($fig);
  
    # sort the cells
    if ($sort eq "Classification")     {@ssa=sort {uc($a->[0]) cmp uc($b->[0]) || uc($a->[1]) cmp uc($b->[1]) || uc($a->[2]) cmp uc($b->[2])} @ssa}
    elsif ($sort eq "Subsystem")       {@ssa=sort {uc($a->[2]) cmp uc($b->[2])} @ssa}
    elsif ($sort eq "Curator")         {@ssa=sort {uc($a->[3]) cmp uc($b->[3])} @ssa}
    elsif ($sort eq "Number of Roles") {@ssa=sort {$a->[4] <=> $b->[4]} @ssa}
    elsif ($sort eq "Version")         {@ssa=sort {$a->[5] <=> $b->[5]} @ssa}
  
    ##### Add the ability to change empty classifications
    
    # get the complete list of classifications
    my %class1=(""=>1); my %class2=(""=>1);
    map {$class1{$_->[0]}++; $class2{$_->[1]}++} @ssa;

  
    # replace empty classifications with the popup_menus and create links
    # Disabled this because it is causing the page to load _very_ slowly as the browser has to render all the menus
    # two alternatives: put only a popup for the first field if both are empty and then a popup for the second if neither are empty
    # or put textfields to allow people to cut/paste.
    
    map {
     my $ss=$_;
     unless (1 || $ss->[0])  # remove the '1 ||' from this line to reinstate the menus
     {
      $ss->[0] = $cgi->popup_menu(-name=>$ss->[2].".class1", -values=>[sort {$a cmp $b} keys %class1]);
      $ss->[1] = $cgi->popup_menu(-name=>$ss->[2].".class2", -values=>[sort {$a cmp $b} keys %class2]);
     }
     $ss->[2]=&ssa_link($fig, $ss->[2], $user);
     $_=$ss;
    } @ssa;

    my $col_hdrs=[["Classification", "th colspan=2 style='text-align: center'"], "Subsystem", "Curator", "Number of Roles", "Version"];
    push @$col_hdrs, "Number of Genomes" if ($cgi->param('showgenomecounts'));
    
    my $tab=HTML->merge_table_rows(\@ssa);
    my $url = &FIG::cgi_url . "/subsys.cgi?user=$user&request=manage_ss";
    my $target = "window$$";
    
    my %sortmenu=(
        unsorted=>"None",
        alphabetic=>"Alphabetical",
        by_pattern=>"Patterns",
        by_phylo=>"Phylogeny",
        by_tax_id=>"Taxonomy",
        by_variant=>"Variant Code",
    );

    push(@$html,
     $cgi->start_form(-action => "subsys.cgi"),
     "<div class='ssinstructions'>\n",
     "Please choose one of the subsystems from this list, or begin working on your own by entering a name in the box at the bottom of the page. ",
     "We suggest that you take some time to look at the subsystems others have developed before working on your own.",
     "<ul><li>Please do not ever edit someone else's spreadsheet</li>\n<li>Please do not open multiple windows to process the same spreadsheet.</li>",
     "<li>Feel free to open a subsystem spreadsheet and then open multiple other SEED windows to access data and modify annotations.</li>",
     "<li>You can access someone else's subsystem spreadsheet using your ID</li>",
     "<li>To change the classification of an unclassified subsystem, choose the desired classification from the menus and click Update Table View</li>");

    push @$html, "<li>You can <a href='$url&manage=mine'>manage your subsystems</a></li>" if ($user);
    push(@$html,
     "<li>You can <a href='$url'>manage all subsystems</a></li>",
     "</ul></div>",
     "<div class='page_settings' style='width: 75%; margin-left: auto; margin-right: auto'>Please enter your username: ", $cgi->textfield(-name=>"user"), "\n",
     "<table border=1>\n",
     "<tr><th>Settings for this page</th><th>Settings for the links to the next page.<br>Change these and click Update Table View.</th></tr>\n",
     "<tr><td>",
        "<table><tr>",
        "<td valign=center>Sort table by</td><td valign=center>",  
        $cgi->popup_menu(-name=>'sortby', -values=>['Classification', 'Subsystem', 'Curator', 'Number of Roles', 'Version'], -default=>$sort), "</td></tr></table\n",
     "</td>\n<td>",
        "<table><tr>",
        "<td valign=center>Show clusters</td><td valign=center>", $cgi->checkbox(-name=>'show_clusters', -label=>''), "</td>\n", 
        "<td valign=center>Default Spreadsheet Sorted By:</td><td valign=center>", 
        $cgi->popup_menu(-name => 'sort', -values => [keys %sortmenu], -labels=>\%sortmenu),
        "</td></tr></table>\n", 
     "</td></tr></table>\n",
     $cgi->submit('Update Table View'), $cgi->reset, $cgi->p,
     "</div>\n",
     &HTML::make_table($col_hdrs,$tab,"Subsystems"),
     $cgi->end_form(),


#    $cgi->h3('To start a new subsystem'), $cgi->p("Please enter the name of the subsystem that you would like to start. You will be provided with a blank",
#    " form that you can fill in with the roles and genomes to create a subsystem like those above."),
#    $cgi->start_form(-action => "subsys.cgi",
#                                 -target => $target,
#                                 -method => 'post'),
#    $cgi->hidden(-name => 'user', -value => $user, -override => 1),
#    $cgi->hidden(-name => 'request', -value => 'new_ssa', -override => 1),
#    "Name of New Subsystem: ",
#    $cgi->textfield(-name => "ssa_name", -size => 50),
#    $cgi->hidden(-name => 'can_alter', -value => 1, -override => 1),
#    $cgi->br,
#
#    $cgi->submit('start new subsystem'),
 );

}
    
#sub make_link_to_painted_diagram{
#    my($fig, $cgi, $html ) = @_;
#    my $new_html = [];  
#    push(@$new_html,"<br><br>");
#    push(@$new_html,"<a href='$FIG_Config::temp_url/painted_diagram.html'>data painted on diagram</a>");
#    push(@$new_html,"<br>");
#    &HTML::show_page($cgi,$new_html);
#    exit;
#}

sub make_link_to_painted_diagram{
    my($fig, $cgi, $html ) = @_;
    my $script = "<script>
    window.open('$FIG_Config::temp_url/painted_diagram.html');
    </script>"; 
    push(@$html,$script);
    &HTML::show_page($cgi,$html);
    exit;
}

sub find_roles_to_color
{
    my ($fig,$cgi,$html)=@_;
    my ($genome_id,$key,$value);
    
    if($cgi->param('att_data_genome_id')){$genome_id = $cgi->param('att_data_genome_id');}
    
    if($cgi->param('color_diagram_by_peg_tag')){$key = $cgi->param('color_diagram_by_peg_tag');}
    
    if($cgi->param('value_to_color')){$value = $cgi->param('value_to_color');}

    my @results;
    if($value eq "all"){
         @results = $fig->get_attributes(undef,$key,undef);
    }
    else{
	@results = $fig->get_attributes(undef,$key,$value);
    }	
    
    my (@pegs,%roles,%p2v);
    foreach my $result (@results){
        my($p,$a,$v,$l)= @$result;
        if($p =~/$genome_id/){
	    push(@pegs,$p);
            $p2v{$p} = $v;
        }
    }
    
    foreach my $peg (@pegs){
        my $value = $p2v{$peg};     
        my $function = $fig->function_of($peg);
        my @function_roles = $fig->roles_of_function($function);
	foreach my $fr (@function_roles){$roles{$fr} = $value;}
    }

    return \%roles;  
}

sub color_diagram_role_by_av 
{

  my ($fig,$cgi,$ss_name,$ss_obj,$roles,$diagram_name)=@_;
  my $dir = "$FIG_Config::temp_url";
  my $genome_id = $cgi->param('att_data_genome_id');
  my $attribute=$cgi->param('color_diagram_by_peg_tag');
  my $diagram_id = "d01";
  
  my @all_diagrams = $ss_obj->get_diagrams();
  foreach my $ad (@all_diagrams){
      if ($diagram_name eq @$ad[1]){
	  $diagram_id = @$ad[0];
      }	  
  }     
  
  my $diagram_html_file = $ss_obj->get_diagram_html_file($diagram_id);
  open(IN2, $diagram_html_file);
  open(OUT2,">$FIG_Config::temp/painted_diagram.html");

  my %role_to_abbr;
  my @r_and_abbr = $ss_obj->roles_with_abbreviations();
  foreach my $r (@r_and_abbr){ 
      $role_to_abbr{@$r[1]} = @$r[0];
  }
 
  my %abbr_to_coords;
  while ($_ = <IN2>){
      chomp($_);
      my @temp = split("<AREA SHAPE",$_);
      foreach my $t (@temp){
	  if( $t =~/COORDS=\"(\d+,\d+,\d+,\d+)\".*Role=\"(\w+)\"/){
                $abbr_to_coords{$2} = $1;
	  }
      }
  }

  print OUT2 qq(<html><head><title>Painted Diagram</title><link rel='stylesheet' title='default' href='../FIG/Html/css/default.css' type='text/css'>
  <link rel='alternate stylesheet' title='Sans Serif' href='../FIG/Html/css/sanserif.css' type='text/css'>
  <link rel='alternate'  title='SEED RSS feeds' href='../FIG/Html/rss/SEED.rss' type='application/rss+xml'>
  <script src="../FIG/Html/css/FIG.js" type="text/javascript"></script></HEAD>
		<script src="../FIG/Html/css/coloring.js" type="text/javascript"></script>);
  
  print OUT2 qq(<style type="text/css">
  .colored {
	background-repeat:repeat;
        border: 0;
	border-style: solid;
        margin: 0;
        border: 0;
        font-size: 8pt;
  }   
   .colored[class] {
	background-image: url(../FIG/Html/diagram_overlay.png);
   }

    .coloredRed {
	background-repeat:repeat;
        border: 0;
	border-style: solid;
        margin: 0;
        border: 0;
        font-size: 8pt;
  }   
   .coloredRed[class] {
	background-image: url(../FIG/Html/diagram_overlay_red.png);
   }
 
  .coloredBlue {
	background-repeat:repeat;
        border: 0;
	border-style: solid;
        margin: 0;
        border: 0;
        font-size: 8pt;
  }   
   .coloredBlue[class] {
	background-image: url(../FIG/Html/diagram_overlay_blue.png);
   }

    .coloredGreen {
	background-repeat:repeat;
        border: 0;
	border-style: solid;
        margin: 0;
        border: 0;
        font-size: 8pt;
  }   
   .coloredGreen[class] {
	background-image: url(../FIG/Html/diagram_overlay_green.png);
   }
  
    .coloredGray {
	background-repeat:repeat;
        border: 0;
	border-style: solid;
        margin: 0;
        border: 0;
        font-size: 8pt;
  }   
   .coloredGray[class] {
	background-image: url(../FIG/Html/diagram_overlay_gray.png);
   }

  .xcolored {
  background-color: red
  }

  .transparent { 
  background-color: transparent
  }
  </style>);
 
  print OUT2 qq(<body onload="onBodyLoad()">);
  print OUT2 qq(<div id="map_div" style="position:relative; left:0px; top:0px;"><MAP NAME="painted_diagram">);
  
  #iterate through roles passed in to subroutine for consideration
  my(@RedRoles,@BlueRoles,@GrayRoles,@GreenRoles);
  foreach my $role (keys(%$roles)){
      my %temp_hash = %$roles;
      if($role_to_abbr{$role}){
          my $abbr =$role_to_abbr{$role};
	  if($abbr_to_coords{$abbr}){
              my $temp = $abbr_to_coords{$abbr};
	      my @coords = split(",",$temp);
	      my $x1 = $coords[0];
	      my $y1 = $coords[1];
	      my $x2 = $coords[2];
	      my $y2 = $coords[3];
              print OUT2 qq(<AREA SHAPE="rect" COORDS="$x1,$y1,$x2,$y2" NOHREF Role="$abbr">);	
              my $value = $temp_hash{$role};
	      if($value eq "essential"){
		  $abbr = "'".$abbr."'"; 
                  push(@RedRoles,$abbr);
	      }
	      elsif($value eq "nonessential"){
                  $abbr = "'".$abbr."'"; 
		  push(@BlueRoles,$abbr);
	      }
	      elsif($value eq "undetermined"){
		  $abbr = "'".$abbr."'"; 
		  push(@GrayRoles,$abbr);
	      }
	      else{
		  $abbr = qq("$abbr"); 
		  push(@GreenRoles,$abbr);
	      }
	  } 
      }
  }
  
  system `cp $FIG_Config::data/Subsystems/$ss_name/diagrams/$diagram_id/diagram.jpg $FIG_Config::temp/painted_diagram.jpg`;
  print OUT2 qq(</MAP><img border="0" src="$FIG_Config::temp_url/painted_diagram.jpg" usemap="#painted_diagram"></div>);

  my $BlueRolesString = join(",",@BlueRoles);
  my $GreenRolesString = join(",",@GreenRoles);
  my $RedRolesString = join(",",@RedRoles);
  my $GrayRolesString = join(",",@GrayRoles);
  
  print OUT2 qq(<script language="JavaScript">
       function onBodyLoad()
       {
	  var rolesToColorGreen = new Array($GreenRolesString);
          var rolesToColorRed = new Array($RedRolesString);
          var rolesToColorBlue = new Array($BlueRolesString);
          var rolesToColorGray = new Array($GrayRolesString);
	  colorEngine = new ActiveDiagram("map_div");
          colorEngine.load();
	  colorEngine.colorRedRoles(rolesToColorRed);
          colorEngine.colorBlueRoles(rolesToColorBlue);
          colorEngine.colorGrayRoles(rolesToColorGray);
	  colorEngine.colorGreenRoles(rolesToColorGreen);
       }
      </script>);
   
  print OUT2 "</BODY></HTML>";
}

sub paint_ma_data 
{

  my ($fig,$cgi,$ss_name,$ss_obj)=@_;
  my @inputs;  
  my $dir = "$FIG_Config::temp_url";
  my $genome_id = $cgi->param('ma_data_genome_id');

  my %peg_to_level;
  my $ma_data = 0;
 
  if ($cgi->upload('ma_data_file'))
  {
      my $fh=$cgi->upload('ma_data_file');
      @inputs = <$fh> ;
      $ma_data = 1; 
      
      foreach my $i (@inputs){
	 chomp($i);
	 my @temp = split("\t",$i);
	 $peg_to_level{$temp[0]} = $temp[1];
     }
  }
 
  my $diagram_html_file = $ss_obj->get_diagram_html_file("d01");
  open(IN2, $diagram_html_file);
  open(OUT2,">$FIG_Config::temp/painted_diagram.html");

  my %role_to_coords;
  
  while ($_ = <IN2>){
      chomp($_);
      my @temp = split("<AREA SHAPE",$_);
      foreach my $t (@temp){
	  
	  if( $t =~/COORDS=\"(\d+,\d+,\d+,\d+)\".*Role=\"(\w+)\"/){
                $role_to_coords{$2} = $1;
          }
      }
  }

  print OUT2 "<HTML><HEAD>
  <TITLE>microarray data painted on subsystem diagram</TITLE>
  </HEAD>";  
 
  print OUT2 "<BODY><MAP NAME='painted_diagram'>";   
 
  my @roles = keys(%role_to_coords);
  my $color; 
  foreach my $role (@roles){
      my $temp = $role_to_coords{$role};
      my @coords = split(",",$temp);
      my @pegs = $ss_obj->get_pegs_from_cell($genome_id,$role);
      foreach my $peg (@pegs){
	  my $temp = $role_to_coords{$role};
	  my @coords = split(",",$temp);
          my $top = $coords[1] - 35;
	  #my $top = $coords[0];
	  my $left = $coords[0] + 15;
	  #my $left = $coords[1];
          if($ma_data){
	      my $tag = $peg_to_level{$peg};
	      if($tag < -.99){$color ="#009900" }
	      elsif($tag < 1){$color ="#FF0099" }		
	      #elsif($tag < .50){$color ="#00FF00" }	
	      #elsif($tag < 2){$color ="#CCFF00" }
	      #elsif($tag < 20){$color ="#FF00FF" }
	      #elsif($tag < 40){$color ="#FF00CC" }
	      #elsif($tag < 80){$color ="#FF0066" }
	      elsif($tag < 100){$color ="#FF0033" }
	      else{$color ="#FF0000" }	
	      print OUT2 "<h5 STYLE='position: absolute; top:$top; left:$left'><font Color='$color'>$tag</font></h5>\n";
	  }
	 # else{
	 #     my @rets = $fig->get_attributes($peg,$attribute);
	 #     foreach my $ret (@rets){
	#	  my($p,$t,$value,$l) = @$ret;
        #          #print STDERR "value:$value\n";
	#	  print OUT2 "<h5 STYLE='position: absolute; top:$top; left:$left'><font Color='$color'>$value</font></h5>\n";
	#      }
	#  }
      }
  }
  
  my $jpg_file  = "$FIG_Config::data/Subsystems/$ss_name/diagrams/d01/diagram.jpg";
  system "cp $jpg_file $FIG_Config::temp/painted_diagram.jpg";

  my $width; 
  my $height;
  
  if($cgi->param('image_file_width')){
     $width = $cgi->param('image_file_width'); 
     $height = $cgi->param('image_file_height');
  }

  print OUT2 "</MAP><IMG SRC='painted_diagram.jpg' WIDTH='$width' HEIGHT='$height' USEMAP='#painted_diagram' BORDER='0'></BODY></HTML>";
}

sub manage_subsystems {
    my($fig,$cgi,$html) = @_;
    my($set,$when,$comment);

    my $ss_to_manage=$cgi->param('manage');  # we will only display a subset of subsystems on the old SS page
    if ($ss_to_manage eq "mine") {$ss_to_manage=$user}
    
    my @ssa = &existing_subsystem_annotations($fig);
    # RAE comment out the next line to hide selection
    $ss_to_manage && (@ssa=grep {$_->[1] eq $ss_to_manage} @ssa); # limit the set if we want to

    if (@ssa > 0)
    {
        &format_ssa_table($cgi,$html,$user,\@ssa);
    }

    my $target = "window$$";
    push(@$html, $cgi->h1('To Start or Copy a Subsystem'),
                 $cgi->start_form(-action => "subsys.cgi",
                                  -target => $target,
                                  -method => 'post'),
                 $cgi->hidden(-name => 'user', -value => $user, -override => 1),
                 $cgi->hidden(-name => 'request', -value => 'new_ssa', -override => 1),
                 "Name of New Subsystem: ",
                 $cgi->textfield(-name => "ssa_name", -size => 50),
                 $cgi->hidden(-name => 'can_alter', -value => 1, -override => 1),
                 $cgi->br,

                 "Copy from (leave blank to start from scratch): ",
                 $cgi->textfield(-name => "copy_from1", -size => 50),
                 $cgi->br,

                 "Copy from (leave blank to start from scratch): ",
                 $cgi->textfield(-name => "copy_from2", -size => 50),
                 $cgi->br,

                 "Rename an existing subsystem: ",
                 $cgi->textfield(-name => "move_from", -size => 50),
                 $cgi->br,

                 $cgi->submit('start new subsystem'),
                 $cgi->end_form,
                 "<br>You can start a subsystem from scratch, in which case you should leave these two \"copy from\"
fields blank.  If you wish to just copy a subsystem (in order to become the owner so that you can modify it),
just fill in one of the \"copy from\" fields with the name of the subsystem you wish to copy.  If you wish to
extract a a subset of the columns to build a smaller spreadsheet (which could later be merged with another one),
fill in the name of the subsystem.  You will be prompted for the columns that you wish to extract (choose <i>all</i> to
just copy all of the columns).  Finally, if you wish to build a new spreadsheet by including columns from two existing
spreadsheets (including a complete merger), fill in the names of both the existing \"copy from\" subsystems"
         );
}                 

sub new_ssa {
    my($fig,$cgi,$html) = @_;

    my $name = $fig->clean_spaces($cgi->param('ssa_name')); # RAE remove extraneous spaces in the name

    if  (! $user)
    {
        push(@$html,$cgi->h1('You need to specify a user before starting a new subsystem annotation'));
        return;
    }

    if  (! $name)
    {
        push(@$html,$cgi->h1("You need to specify a subsystem name, $name is not valid"));
        return;
    }

    my $ssa  = $name;
    $ssa =~ s/[ \/]/_/g;

    &FIG::verify_dir("$FIG_Config::data/Subsystems");

    if (-d "$FIG_Config::data/Subsystems/$ssa")
    {
        push(@$html,$cgi->h1("You need to specify a new subsystem name; $ssa already is being used"));
        return;
    }

    my $subsystem = new Subsystem($ssa,$fig,1);    # create new subsystem

    my $copy_from1 = $cgi->param('copy_from1');
    $copy_from1 =~ s/[ \/]/_/g;
    my $copy_from2 = $cgi->param('copy_from2');
    $copy_from2 =~ s/[ \/]/_/g;
    my @cols_to_take1 = $cgi->param('cols_to_take1');
    my @cols_to_take2 = $cgi->param('cols_to_take2');

    
    if ($copy_from1 && (@cols_to_take1 > 0))
    {
        $subsystem->add_to_subsystem($copy_from1,\@cols_to_take1,"take notes");  # add columns and notes
    }

    if ($copy_from2 && (@cols_to_take2 > 0))
    {
        $subsystem->add_to_subsystem($copy_from2,\@cols_to_take2,"take notes");  # add columns and notes
    }

    $subsystem->db_sync();
    $subsystem->write_subsystem();

    $cgi->param(-name  => "ssa_name",
                -value => $ssa); # RAE this line was needed because otherwise a newly created subsystem was not opened!
    $cgi->param(-name  => "can_alter",
                -value => 1);
    &one_cycle($fig,$cgi,$html);
}

# The basic update logic (cycle) includes the following steps:
# 
#     1. Load the existing spreadsheet
#     2. reconcile row and subset changes
#     3. process spreadsheet changes (fill/refill/add genomes/update variants)
#     4. write the updated spreadsheet back to disk
#     5. render the spreadsheet
#
sub one_cycle {
    my($fig,$cgi,$html) = @_;
    my $subsystem;

    my $ssa  = $cgi->param('ssa_name');

    if  ((! $ssa) || (! ($subsystem = new Subsystem($ssa,$fig,0))))
    {
        push(@$html,$cgi->h1('You need to specify a subsystem'));
        return;
    }

    #
    # Initialize can_alter if it is not set.
    #

    my $can_alter = $cgi->param("can_alter");
    if (!defined($can_alter))
    {
        if ($user and ($user eq $subsystem->get_curator))
        {
            $can_alter = 1;
            $cgi->param(-name => 'can_alter', -value => 1);
        }
    }

    #
    # If we're not the curator, force the active subsets to All.
    #

    if (not $can_alter)
    {
        $subsystem->set_active_subsetC("All");
        $subsystem->set_active_subsetR("All");
    }
    
    if ($cgi->param('can_alter') && $user && ($user eq $subsystem->get_curator))
    {
        handle_diagram_changes($fig, $subsystem, $cgi, $html);
    }

    if (&handle_role_and_subset_changes($fig,$subsystem,$cgi,$html))
    {
        &process_spreadsheet_changes($fig,$subsystem,$cgi,$html);

        if ($cgi->param('can_alter') && $user && ($user eq $subsystem->get_curator))
        {
            $subsystem->write_subsystem();
            # RAE: Adding a call to HTML.pm to write the changes to the RSS feed. Not 100% sure we want to do this
            # everytime we write a SS, but we'll see

            # note in the RSS we want a barebones link because anyone can access it.
            my $esc_ssa=uri_escape($ssa);
            my $url = &FIG::cgi_url . "/subsys.cgi?user=&ssa_name=$esc_ssa&request=show_ssa";

            &HTML::rss_feed(
            ["SEEDsubsystems.rss"], 
            {
              "title"           => "Updated $ssa",
              "description"     => "$ssa was updated with some changes, and saved",
              "link"            => $url,
            });
        }

        my $col;
        if ($cgi->param('show_sequences_in_column') && 
            ($col = $cgi->param('col_to_align')) && 
            ($col =~ /^\s*(\d+)\s*$/))
        {
            &show_sequences_in_column($fig,$cgi,$html,$subsystem,$col);
        }
        else
        {
            if ($cgi->param('align_column') && 
                ($col = $cgi->param('col_to_align')) && ($col =~ /^\s*(\d+)\s*$/))
            {
                my $col = $1;
                &align_column($fig,$cgi,$html,$col,$subsystem);
                $cgi->delete('col_to_align');
            }
            elsif ($cgi->param('realign_column') &&
                   ($col = $cgi->param('subcol_to_realign')) && ($col =~ /^\s*(\d+)\.(\d+)\s*$/))
            {
                &align_subcolumn($fig,$cgi,$html,$1,$2,$subsystem);
                $cgi->delete('subcol_to_realign');
            }
            &produce_html_to_display_subsystem($fig,$subsystem,$cgi,$html,$ssa);
        }
    }
}

sub handle_role_and_subset_changes {
    my($fig,$subsystem,$cgi,$html) = @_;

    if ((! $cgi->param('can_alter')) || (!$user) || ($user ne $subsystem->get_curator))
    {
        return 1;    # no changes, so...
    }
    else
    {
        my @roles = $subsystem->get_roles;
        my($rparm,$vparm);
        foreach $rparm (grep { $_ =~ /^react\d+/ } $cgi->param)
        {
            if ($vparm = $cgi->param($rparm))
            {
                $vparm =~ s/ //g;
                $rparm =~ /^react(\d+)/;
                my $roleN  = $1 - 1;
                $subsystem->set_reaction($roles[$roleN],$vparm);
            }
        }

        foreach $rparm (grep { $_ =~ /^hopeReact\d+/ } $cgi->param)
        {
            if ($vparm = $cgi->param($rparm))
            {
                $vparm =~ s/ /,/g;
                $vparm =~ s/,+/,/g;
                $rparm =~ /^hopeReact(\d+)/;
                my $roleN  = $1 - 1;
                $subsystem->set_hope_reaction($roles[$roleN],$vparm);
            }
        }

        foreach $rparm (grep { $_ =~ /^hopeNote\d+/ } $cgi->param)
        {
            if ($vparm = $cgi->param($rparm))
            {
                $vparm =~ s/\t/ /g;
                $rparm =~ /^hopeNote(\d+)/;
                my $roleN  = $1 - 1;
                $subsystem->set_hope_reaction_note($roles[$roleN],$vparm);
            }
        }

        my($role,$p,$abr,$r,$n);
        my @tuplesR = ();

###     NOTE: the meaning (order) of @roles shifts here to the NEW order
        @roles   = grep { $_ =~ /^role/ }   $cgi->param();
        if (@roles == 0)  { return 1 }     # initial call, everything is as it was

        foreach $role (@roles)
        {
            if (($role =~ /^role(\d+)/) && defined($n = $1))
            {
                if ($r = $cgi->param("role$n"))
                {
                    $r =~ s/^\s+//;
                    $r =~ s/\s+$//;

                    if (($p = $cgi->param("posR$n")) && ($abr = $cgi->param("abbrev$n")))
                    {
                        push(@tuplesR,[$p,$r,$abr,$n]);
                    }
                    else
                    {
                        push(@$html,$cgi->h1("You need to give a position and abbreviation for $r"));
                        return 0;
                    }
                }
            }
        }
        @tuplesR = sort { $a->[0] <=> $b->[0] } @tuplesR;

        $subsystem->set_roles([map { [$_->[1],$_->[2]] } @tuplesR]);

        my($subset_name,$s,$test,$entries,$entry);
        my @subset_names  = grep { $_ =~ /^nameCS/ } $cgi->param();

        if (@subset_names == 0) { return 1 }

        my %defined_subsetsC;
        foreach $s (@subset_names)
        {
            if (($s =~ /^nameCS(\d+)/) && defined($n = $1) && ($subset_name = $cgi->param($s)))
            {

                my($text);
                $entries = [];
                if ($text = $cgi->param("subsetC$n"))
                {
                    foreach $entry (split(/[\s,]+/,$text))
                    {
                        if ($role = &to_role($entry,\@tuplesR))
                        {
                            push(@$entries,$role);
                        }
                        else
                        {
                            push(@$html,$cgi->h1("Invalid role designation in subset $s: $entry"));
                            return 0;
                        }
                    }
                }
                $defined_subsetsC{$subset_name} = $entries;
            }
        }

        foreach $s ($subsystem->get_subset_namesC)
        {
            next if ($s eq "All");
            if ($entries = $defined_subsetsC{$s})
            {
                $subsystem->set_subsetC($s,$entries);
                delete $defined_subsetsC{$s};
            }
            else
            {
                $subsystem->delete_subsetC($s);
            }
        }

        foreach $s (keys(%defined_subsetsC))
        {
            $subsystem->set_subsetC($s,$defined_subsetsC{$s});
        }

        my $active_subsetC;
        if ($active_subsetC = $cgi->param('active_subsetC'))
        {
            $subsystem->set_active_subsetC($active_subsetC);
        }
    }
    return 1;
}

sub to_role {
    my($x,$role_tuples) = @_;
    my $i;

    for ($i=0; ($i < @$role_tuples) && 
               ($role_tuples->[$i]->[3] != $x) &&
               ($role_tuples->[$i]->[2] ne $x); $i++) {}
    if ($i < @$role_tuples)
    {
        return $role_tuples->[$i]->[1];
    }
    return undef;
}
    
sub process_spreadsheet_changes {
    my($fig,$subsystem,$cgi,$html) = @_;

    if ((! $cgi->param('can_alter')) || (!$user) || ($user ne $subsystem->get_curator))
    {
        return 1;    # no changes, so...
    }
    else
    {
	my @hope_scenario_names = $subsystem->get_hope_scenario_names;

	foreach my $scenario_name (@hope_scenario_names)
	{
	    my $inputcpd = $cgi->param($scenario_name.'_InputCompounds');
	    if($inputcpd ne "")
	    {
		$subsystem->set_hope_input_compounds($scenario_name, $inputcpd);
	    }
	    my $outputcpd = $cgi->param($scenario_name.'_OutputCompounds');
	    if($outputcpd ne "")
	    {
		$subsystem->set_hope_output_compounds($scenario_name, $outputcpd);
	    }
	    my $mapIDs = $cgi->param($scenario_name.'_MapIDs');
	    if($mapIDs ne "")
	    {
		$subsystem->set_hope_map_ids($scenario_name, $mapIDs);
	    }
	    my $addRxns = $cgi->param($scenario_name.'_AddRxns');
	    if($addRxns ne "")
	    {
		$subsystem->set_hope_additional_reactions($scenario_name, $addRxns);
	    }
	    my $ignoreRxns = $cgi->param($scenario_name.'_IgnoreRxns');
	    if($ignoreRxns ne "")
	    {
		$subsystem->set_hope_ignore_reactions($scenario_name, $ignoreRxns);
	    }
	    my $new_name = $cgi->param($scenario_name."_Name");
	    if ($new_name ne "")
	    {
		$new_name =~ s/\//_/g;
		$new_name =~ s/\,/_/g;
		$new_name =~ s/ /_/g;
		$new_name =~ s/-/_/g;
		$subsystem->change_hope_scenario_name($scenario_name, $new_name);
	    }
	    if ($cgi->param($scenario_name."_Delete"))
	    {
		$subsystem->delete_hope_scenario($scenario_name);
	    }
	}
	my $new_name = $cgi->param("newscenario_Name");
	if ($new_name ne "")
	{
	    $new_name =~ s/\//_/g;
	    $new_name =~ s/\,/_/g;
	    $new_name =~ s/ /_/g;
	    $new_name =~ s/-/_/g;
	    $subsystem->add_hope_scenario($new_name);
	}

        my $notes = $cgi->param('notes');
        if ($notes)
        {
            $subsystem->set_notes($notes);
        }

	## as description and notes are now separate, I (DB) put in this for description
        my $description = $cgi->param('description');
        if ($description)
        {
            $subsystem->set_description($description);
        }
	## end of added code

        my $hope_curation_notes = $cgi->param('hope_curation_notes');
        if ($hope_curation_notes)
        {
            $subsystem->set_hope_curation_notes($hope_curation_notes);
        }
        if ($cgi->param('classif1t') || $cgi->param('classif2t')) 
        {
         $subsystem->set_classification([$cgi->param('classif1t'), $cgi->param('classif2t')]);
        }
        elsif ($cgi->param('classif1') || $cgi->param('classif2'))
        {
         $subsystem->set_classification([$cgi->param('classif1'), $cgi->param('classif2')]);
        }

        my(@param,$param,$genome,$val);
        @param = grep { $_ =~ /^genome\d+\.\d+$/ } $cgi->param;

        my %removed;
        foreach $param (@param)
        {
            if ($cgi->param($param) =~ /^\s*$/)
            {
                $param =~ /^genome(\d+\.\d+)/;
                $genome = $1;
                $subsystem->remove_genome($genome);
                $removed{$genome} = 1;
            }
        }

        @param = grep { $_ =~ /^vcode\d+\.\d+$/ } $cgi->param;
        foreach $param (@param)
        {
            if ($cgi->param($param) =~ /^\s*(\S+)\s*$/)
            {
                $val = $1;
                $param =~ /^vcode(\d+\.\d+)/;
                $genome = $1;
                if (! $removed{$genome})
                {
                    $subsystem->set_variant_code($subsystem->get_genome_index($genome),$val);
                }
            }
        }
        
        if ($cgi->param('refill'))
        {
            &refill_spreadsheet($fig,$subsystem);
        }
        elsif ($cgi->param('precise_fill'))
        {
            &fill_empty_cells($fig,$subsystem);
        }

        my @orgs = $cgi->param('new_genome');
        @orgs = map { $_ =~ /\((\d+\.\d+)\)/; $1 } @orgs;

        # RAE: Add organisms to extend with from checkboxes
        # moregenomes takes either a specifically encoded list like phylogeny, a file that must be present in the organisms dir (e.g. COMPLETE or NMPDR)
        # or a set of attributes
        if ($cgi->param('moregenomes')) {push @orgs, &moregenomes}

    
        # flatten the list so we don't add more than we need to
        {
            my %flatlist=map {($_=>1)} @orgs;
            @orgs=keys %flatlist;
        }
        
        my $org;
        foreach $org (@orgs)
        {
            &add_genome($fig,$subsystem,$cgi,$html,$org);
        }

        my $active_subsetR;
        if ($active_subsetR = $cgi->param('active_subsetR'))
        {
            $subsystem->set_active_subsetR($active_subsetR);
        }
    }
}

sub refill_spreadsheet {
    my($fig,$subsystem) = @_;
    my($genome,$role,@pegs1,@pegs2,$i);

    foreach $genome ($subsystem->get_genomes())
    {
        foreach $role ($subsystem->get_roles())
        {
            @pegs1 = sort $subsystem->get_pegs_from_cell($genome,$role);
            @pegs2 = sort $fig->seqs_with_role($role,"master",$genome);

            if (@pegs1 != @pegs2)
            {
                $subsystem->set_pegs_in_cell($genome,$role,\@pegs2);
            }
            else
            {
                for ($i=0; ($i < @pegs1) && ($pegs1[$i] eq $pegs2[$i]); $i++) {}
                if ($i < @pegs1)
                {
                    $subsystem->set_pegs_in_cell($genome,$role,\@pegs2);
                }
            }
        }
    }
}

sub fill_empty_cells {
    my($fig,$subsystem) = @_;
    my($genome,$role,@pegs);

    foreach $genome ($subsystem->get_genomes())
    {
        foreach $role ($subsystem->get_roles())
        {
            @pegs = $subsystem->get_pegs_from_cell($genome,$role);
            if (@pegs == 0)
            {
                @pegs = $fig->seqs_with_role($role,"master",$genome);
                if (@pegs > 0)
                {
                    $subsystem->set_pegs_in_cell($genome,$role,\@pegs);
                }
            }
        }
    }
}

sub add_genome {
    my($fig,$subsystem,$cgi,$html,$genome) = @_;
    my($role,@pegs);
    
    $subsystem->add_genome($genome);
    foreach $role ($subsystem->get_roles())
    {
        @pegs = $fig->seqs_with_role($role,"master",$genome);
        $subsystem->set_pegs_in_cell($genome,$role,\@pegs);
    }
}

sub produce_html_to_display_subsystem {
    my($fig,$subsystem,$cgi,$html,$ssa) = @_;

    my $ssa  = $cgi->param('ssa_name');
    my $compuser = $user;
    $compuser =~ s/master\://g;
    my $curateuser = $subsystem->get_curator;
    $curateuser =~ s/master\://g;

    my $can_alter = ($cgi->param('can_alter') && $user && ($compuser eq $curateuser));

    my $tagvalcolor; # RAE: this is a reference to a hash that stores the colors of cells by tag. This has to be consistent over the whole table.

    my $name  = $ssa;
    $name =~ s/_/ /g;
    $ssa =~ s/[ \/]/_/g;
    my $curator = &subsystem_curator($ssa);

    push(@$html, $cgi->h1("Subsystem: $name"),
	         $cgi->h1("Author: $curator"));
   
    my($t,@spreadsheets);
    if (opendir(BACKUP,"$FIG_Config::data/Subsystems/$ssa/Backup"))
    {
        @spreadsheets = sort { $b <=> $a }
                        map { $_ =~ /^spreadsheet.(\d+)/; $1 }
                        grep { $_ =~ /^spreadsheet/ } 
                        readdir(BACKUP);
        closedir(BACKUP);
        if ($t = shift @spreadsheets)
        {
            my $last_modified = &FIG::epoch_to_readable($t);
	    push(@$html, $cgi->h1("Last modified: $last_modified"));
	}
    }

    if ( $time_it )                  ## time ##
    {                                ## time ##
        push @times, scalar time();  ## time ##
        push @$html, "<br>dT = @{[$times[-1]-$times[-2]]}, T = @{[$times[-1]-$times[0]]}<br>";  ## time ##
    }                                ## time ##

    push(@$html, $cgi->start_form(-action => "subsys.cgi",
                                  -method => 'post',
				  -name => 'MainForm',
                                  -enctype => &CGI::MULTIPART),
                 $cgi->hidden(-name => 'user', -value => $user, -override => 1),
                 $cgi->hidden(-name => 'request', -value => 'show_ssa', -override => 1),
                 $cgi->hidden(-name => 'can_alter', -value => $can_alter, -override => 1),
                 $cgi->hidden(-name => 'ssa_name', -value => $name, -override => 1),
                 $cgi->br,
         );

    # RAE: First, a sanity check.
    # We may have to move this a little earlier, and show probably throw some nicer
    # errors to the end user (.e.g try setting can_alter and choosing an illegitimate ss
    # Do we know about this subsystem:
    my $ssaQ = quotemeta $ssa;

    if (! -d "$FIG_Config::data/Subsystems/$ssa")
######    unless (grep {/$ssaQ/} map {$_->[0]} &existing_subsystem_annotations($fig))
    {
     # No, we don't know about this subsystem
     my $url = &FIG::cgi_url . "/subsys.cgi?user=$user";
     push @$html, "Sorry. $name is not a valid subsystem. <p>\n",
     "Please return to the <a href=\"$url\">Subsystems Page</a> and choose an exisiting subsystem. <p>\n",
     "Sorry.";
     return undef;
    }
    
    &format_js_data($fig,$cgi,$html,$subsystem,$can_alter);

    &format_roles($fig,$cgi,$html,$subsystem,$can_alter);
    &format_subsets($fig,$cgi,$html,$subsystem,$can_alter);


    my $have_diagrams = &format_diagrams($fig, $cgi, $html, $subsystem, $can_alter);

    #
    # Put link into constructs tool.
    #

    if ($can_alter)
    {
	my $esc_ssa = uri_escape($ssa);
        push(@$html, $cgi->p,
             $cgi->a({href => "construct.cgi?ssa=$esc_ssa&user=$user",
                          target => "_blank"},
                     "Define higher level constructs."),
             $cgi->p,
	     $cgi->a({href => "set_variants.cgi?subsystem=$esc_ssa&user=$user&request=show_variants"},
		     "Set subsystem variants."),
	     );
	

    }


    #  Display the subsystem table rows, saving the list genomes displayed

    my $active_genome_list = &format_rows($fig,$cgi,$html,$subsystem, $tagvalcolor,$have_diagrams);


    if ( $can_alter ) { format_extend_with($fig,$cgi,$html,$subsystem) }

    my $esc_ssa = uri_escape( $ssa );
    push @$html, "<TABLE width=\"100%\">\n",
                 "    <TR>\n",
                 ($can_alter) ? "        <TD>" . $cgi->checkbox(-name => 'precise_fill', -value => 1, -checked => 0, -override => 1,-label => 'fill') . "</TD>\n" : (),
                     "        <TD><a href=\"Html/conflict_resolution.html\" class=\"help\" target=\"help\">Help on conflict resolution</a></TD>\n",
                     "        <TD><a href=\"Html/seedtips.html#edit_variants\" class=\"help\" target=\"help\">Help on editing variants</a></TD>\n",
		     "        <TD><a href=\"Html/seedtips.html#make_trees\" class=\"help\" target=\"help\">Help on making trees</a></td>\n",
                     "        <TD><a href=\"ss_export.cgi?user=$user&ssa_name=$esc_ssa\" class=\"help\">Export subsystem data</a></TD>\n",
                 "    </TR>\n",
                 "</TABLE>\n";
    
    if ($can_alter)
    {
        push(@$html,$cgi->submit('update spreadsheet')," OR ");
    }
    else
    {
        push(@$html,$cgi->br);
        push(@$html,$cgi->submit('show spreadsheet'),$cgi->br);
    }
  
  
    push(@$html,$cgi->checkbox(-name => 'ignore_alt', -value => 1, -override => 1, -label => 'ignore alternatives', -checked => ($cgi->param('ignore_alt'))),$cgi->br);
    push(@$html,$cgi->checkbox(-name => 'ext_ids', -value => 1, -checked => 0, -label => 'use external ids'),$cgi->br);
    push(@$html,$cgi->checkbox(-name => 'show_clusters', -value => 1, -label => 'show clusters'),$cgi->br);

    my @options = ();
    @options = sort {uc($a) cmp uc($b)} $fig->get_genome_keys(); # get all the genome keys
    unshift(@options, undef); # a blank field at the start
    push(@$html,"color rows by each organism's attribute: &nbsp; ", $cgi->popup_menu(-name => 'color_by_ga', -values=>\@options), $cgi->br);

    #  Compile and order the attribute keys found on pegs:

    my $high_priority = qr/(essential|fitness)/i;
    @options = sort { $b =~ /$high_priority/o <=> $a =~ /$high_priority/o
                   || uc($a) cmp uc($b)
                    }
               $fig->get_peg_keys();
    unshift @options, undef;  # Start list with empty

    push( @$html, "color columns by each PEGs attribute: &nbsp; ",
                  $cgi->popup_menu(-name => 'color_by_peg_tag', -values=>\@options),
                  $cgi->br
        );

    if ( $time_it )                  ## time ##
    {                                ## time ##
        push @times, scalar time();  ## time ##
        push @$html, "<br>dT = @{[$times[-1]-$times[-2]]}, T = @{[$times[-1]-$times[0]]}<br>";  ## time ##
    }                                ## time ##

    push @$html, $cgi->checkbox(-name => 'show_missing', -value => 1, -checked => 0, -override => 1,-label => 'show missing'),
                 $cgi->br, $cgi->br;


    #  Format the organism list for a pop-up menu:

    my @genomes = sort { lc $a->[1] cmp lc $b->[1] } map { [ $_->[0], "$_->[1] [$_->[0]]" ] } @$active_genome_list;
    unshift @genomes, [ '', 'select it in this menu' ];

    # Make a list of index number and roles for pop-up selections:

    my @roles = map { [ $subsystem->get_role_index( $_ ) + 1, $_ ] } $subsystem->get_roles;
    unshift @roles, [ '', 'select it in this menu' ];

    push @$html,  "<table><tr><td>",
                  $cgi->checkbox(-name => 'show_missing_including_matches', -value => 1, -checked => 0, -override => 1,-label => 'show missing with matches'), $cgi->br,
                  $cgi->checkbox(-name => 'show_missing_including_matches_in_ss', -value => 1, -checked => 0, -override => 1,-label => 'show missing with matches in ss'), "&nbsp;&nbsp;",
                  "</td>\n<td><big><big><big>} {</big></big></big></td>",
                  "<td>",
                  "[To restrict to a single genome: ",
                  $cgi->popup_menu( -name   => 'just_genome',
                                    -values => [ map {   $_->[0]            } @genomes ],
                                    -labels => { map { ( $_->[0], $_->[1] ) } @genomes }
                                  ), "]", $cgi->br,
                  "[To restrict to a single role: ",
                  $cgi->popup_menu( -name   => 'just_role',
                                    -values => [ map {   $_->[0]            } @roles ],
                                    -labels => { map { ( $_->[0], $_->[1] ) } @roles }
                                  ),
                  "]</td></tr></table>\n",
                  $cgi->br;


    push @$html,  "<table><tr><td>",
                  $cgi->checkbox(-name => 'check_assignments', -value => 1, -checked => 0, -override => 1, -label => 'check assignments'),
                  "&nbsp;&nbsp;[", $cgi->checkbox(-name => 'strict_check', -value => 1, -checked => 0, -override => 1, -label => 'strict'), "]&nbsp;&nbsp;",
                  "</td>\n<td><big><big><big>{</big></big></big></td>",
                  "<td>",
                  "[To restrict to a single genome: ",
                  $cgi->popup_menu( -name   => 'just_genome_assignments',
                                    -values => [ map {   $_->[0]            } @genomes ],
                                    -labels => { map { ( $_->[0], $_->[1] ) } @genomes }
                                  ), "]", $cgi->br,
                  "[To restrict to a single role: ",
                  $cgi->popup_menu( -name   => 'just_role_assignments',
                                    -values => [ map {   $_->[0]            } @roles ],
                                    -labels => { map { ( $_->[0], $_->[1] ) } @roles }
                                  ),
                  "]</td></tr></table>\n",
                  $cgi->br;


    if ( $time_it )                  ## time ##
    {                                ## time ##
        push @times, scalar time();  ## time ##
        push @$html, "<br>dT = @{[$times[-1]-$times[-2]]}, T = @{[$times[-1]-$times[0]]}<br>";  ## time ##
    }                                ## time ##

    if ($can_alter)
    {
        push(@$html,$cgi->checkbox(-name => 'refill', -value => 1, -checked => 0, -override => 1,-label => 'refill spreadsheet from scratch'),$cgi->br);
    }

    push(@$html,$cgi->checkbox(-name => 'show_dups', -value => 1, -checked => 0, -override => 1,-label => 'show duplicates'),$cgi->br);
    push(@$html,$cgi->checkbox(-name => 'check_problems', -value => 1, -checked => 0, -override => 1,-label => 'show PEGs in roles that do not match precisely'),$cgi->br);
    if ($can_alter)
    {
        push(@$html,$cgi->checkbox(-name => 'add_solid', -value => 1, -checked => 0, -override => 1,-label => 'add genomes with solid hits'),$cgi->br);
    }

    push(@$html,$cgi->checkbox(-name => 'show_coupled_fast', -value => 1, -checked => 0, -override => 1,-label => 'show coupled PEGs fast [depends on existing pins/clusters]'),$cgi->br);

    push(@$html,$cgi->checkbox(-name => 'show_coupled', -value => 1, -checked => 0, -override => 1,-label => 'show coupled PEGs [figure 2 minutes per PEG in spreadsheet]'),$cgi->br);

    # RAE Hide -1 variants
    push(@$html,$cgi->checkbox(-name => 'show_minus1', -value=> 1, -label => 'show -1 variants'),$cgi->br);

    # RAE Create excel spreadsheet of tables
    push(@$html, $raelib->excel_file_link, $cgi->checkbox(-name => 'create_excel', -value=> 1, -label => "Create Excel file of tables"), $cgi->br, "\n");
        

    #  Alignment functions:

    push @$html, $cgi->hr,
                 # $cgi->br, "Column (specify the number of the column): ",
                 # $cgi->textfield(-name => "col_to_align", -size => 7),
                 "For sequences in a column (i.e., role): ",
                 $cgi->popup_menu( -name   => 'col_to_align',
                                   -values => [ map {   $_->[0]            } @roles ],
                                   -labels => { map { ( $_->[0], $_->[1] ) } @roles }
                                 ),
                 $cgi->br,
                 $cgi->submit(-value => "Show Sequences in Column",
                              -name  => "show_sequences_in_column"),
                 $cgi->br,
                 $cgi->submit(-value => "Align Sequences in Column",
                              -name  => "align_column"),
                 $cgi->br,
                 $cgi->br, "Realign subgroup within a column (adding homologs): ",
                 $cgi->textfield(-name => "subcol_to_realign", -size => 7),
                 $cgi->br, "Include homologs that pass the following threshhold: ",
                 $cgi->textfield(-name => "include_homo", -size => 10)," (leave blank to see just column)",
                 " Max homologous seqs: ",$cgi->textfield(-name => "max_homo", -value => 100, -size => 6),
                 $cgi->br,
                 $cgi->submit(-value => "Realign Sequences in Column",
                              -name  => "realign_column"),
                 $cgi->hr;

    if ( $time_it )                  ## time ##
    {                                ## time ##
        push @times, scalar time();  ## time ##
        push @$html, "<br>dT = @{[$times[-1]-$times[-2]]}, T = @{[$times[-1]-$times[0]]}<br>";  ## time ##
    }                                ## time ##

     # RAE: A new function to reannotate a single column
     # I don't understand how you get CGI.pm to reset (and never have).
     # $cgi->delete("col_to_annotate"); # this does nothing to my script and there is always the last number in this box
     #push(@$html, $cgi->br,"Change annotation for column: ", $cgi->textfield(-name => "col_to_annotate", -size => 7));
    
     push(@$html, $cgi->br,"Change annotation for column: ", '<input type="text" name="col_to_annotate" value="" size="7">');
    push (@$html, $cgi->hr);
    push(@$html, $cgi->br,"Curate Literature: ", "<a href=display_subsys.cgi?ssa_name=$ssa> Display Subsys </a>");
    if ($can_alter)
    {
        push(@$html,
             $cgi->p. $cgi->hr,
             $cgi->p,
             $cgi->hr,
             "You should resynch PEG connections only if you detect PEGs that should be connected to the
              spreadsheet, but do not seem to be.  This can only reflect an error in the code.  If you find
              yourself having to use it, send mail to Ross.",
             $cgi->br,
             $cgi->submit(-value => "Resynch PEG Connections",
                          -name => "resynch_peg_connections"),
             $cgi->br);
    }

    if ( $time_it )                  ## time ##
    {                                ## time ##
        push @times, scalar time();  ## time ##
        push @$html, "<br>dT = @{[$times[-1]-$times[-2]]}, T = @{[$times[-1]-$times[0]]}<br>";  ## time ##
    }                                ## time ##

    ## as description and notes are now separate, I (DB) put in this for description 
    my $description = $subsystem->get_description();
    if ($can_alter)
    {
        push(@$html,$cgi->hr,"DESCRIPTION:\n",$cgi->br,$cgi->textarea(-name => 'description', -rows => 30, -cols => 100, -value => $description));
    }
    elsif ($description)
    {
        $description =~ s/(.{80}\s+)/$1\n/g;
        push(@$html,$cgi->h2('Description'),"<pre>$description</pre>");
    }
    ## end of added code

    my $notes = $subsystem->get_notes();
    if ($can_alter)
    {
        push(@$html,$cgi->hr,"NOTES:\n",$cgi->br,$cgi->textarea(-name => 'notes', -rows => 30, -cols => 100, -value => $notes));
    }
    elsif ($notes)
    {
        $notes =~ s/(.{80}\s+)/$1\n/g;
        push(@$html,$cgi->h2('Notes'),"<pre>$notes</pre>");
    }

    my $hope_curation_notes = $subsystem->get_hope_curation_notes();
    if ($can_alter)
    {
        push(@$html,$cgi->hr,"HOPE CURATION NOTES:\n",$cgi->br,$cgi->textarea(-name => 'hope_curation_notes', -rows => 40, -cols => 100, -value => $hope_curation_notes));
    }
    elsif ($hope_curation_notes)
    {
        push(@$html,$cgi->h2('hope curation notes'),"<pre width=80>$hope_curation_notes</pre>");
    }

    if ( $time_it )                  ## time ##
    {                                ## time ##
        push @times, scalar time();  ## time ##
        push @$html, "<br>dT = @{[$times[-1]-$times[-2]]}, T = @{[$times[-1]-$times[0]]}<br>";  ## time ##
    }                                ## time ##

    &format_kegg_info($fig,$cgi,$html,$subsystem,$can_alter, $active_genome_list);

    # RAE Modified to add a line with the classification
    my $class=$subsystem->get_classification();
    if ($can_alter)
    {
       my $menu1; my $menu2; # the two menus for the classification of subsystems
       # make sure we have empty blanks
       $menu1->{''}=$menu2->{''}=1;
       map {$menu1->{$_->[0]}=1; $menu2->{$_->[1]}=1} $fig->all_subsystem_classifications();
       
       push(@$html, $cgi->hr, "<table><tr><th colspan=2 style='text-align: center'>Subsystem Classification</th></tr>\n",
        "<tr><td>Please use ours:</td><td>", $cgi->popup_menu(-name=>"classif1", -values=>[sort {$a cmp $b} keys %$menu1], -default=>$$class[0]), "</td><td>",
        $cgi->popup_menu(-name=>"classif2", -values=>[sort {$a cmp $b} keys %$menu2], -default=>$$class[1]), "</td></tr>\n<tr><td>Or make your own:</td><td>",
        $cgi->textfield(-name=>"classif1t", -size=>50), "</td><td>", $cgi->textfield(-name=>"classif2t", -size=>50), "</td></tr></table>\n"
        );
    }
    elsif ($class)
    {
       push (@$html, $cgi->h2('Classification'), "<table><tr><td>$$class[0]</td><td>$$class[1]</td></tr></table>\n");
    }

    if ( $time_it )                  ## time ##
    {                                ## time ##
        push @times, scalar time();  ## time ##
        push @$html, "<br>dT = @{[$times[-1]-$times[-2]]}, T = @{[$times[-1]-$times[0]]}<br>";  ## time ##
    }                                ## time ##

    my @orgs = map { "$_->[0]: " . $_->[1] } 
               sort { $a->[1] cmp $b->[1] }
               map { [$_,$fig->genus_species($_)] }
               grep { $subsystem->get_variant_code($subsystem->get_genome_index($_)) ne "-1" }
               $subsystem->get_genomes;
    my @roles = $subsystem->get_roles;
    push(@$html,$cgi->hr,$cgi->h1('Lock PEGs in Cells'));
    push(@$html, $cgi->scrolling_list( -name     => 'genome_to_lock',
                                       -values   => [ @orgs ],
                                        -size     => 10,
                                        -multiple => 1
				       ),
	         $cgi->br,  # Was unquoted <br>; read from undefined file handle
	         $cgi->scrolling_list(  -name     => 'roles_to_lock',
                                        -values   => [ @roles ],
                                        -size     => 10,
                                        -multiple => 1
					),
                 $cgi->br
        );

    push(@$html,$cgi->submit('lock annotations')," OR ");
    push(@$html,$cgi->submit('unlock annotations'),$cgi->br);

    push(@$html, $cgi->end_form);

    my $target = "align$$";
    my @roles = $subsystem->get_roles;
    my $i;
    my $dir = $subsystem->get_dir;
    my $rolesA = &existing_trees($dir,\@roles);
    
    if (@$rolesA > 0)
    {
        push(@$html, $cgi->hr,
                     $cgi->h1('To Assign Using a Tree'),
                     $cgi->start_form(-action => "assign_using_tree.cgi",
                                      -target => $target,
                                      -method => 'post'),
                     $cgi->hidden(-name => 'user', -value => $user, -override => 1),
                     $cgi->hidden(-name => 'ali_dir', -value => "$dir/Alignments", -override => 1),
                     $cgi->scrolling_list(-name => 'ali_num',
                                          -values => $rolesA,
                                          -size => 10,
                                          -multiple => 0
                                          ),
                     $cgi->br,
                     $cgi->submit(-value => "use_tree",
                                  -name => "use_tree"),
                     $cgi->end_form
         );
    }

    push(@$html, $cgi->hr);

    if ($cgi->param('show_missing'))
    {
        &format_missing($fig,$cgi,$html,$subsystem);
    }

    if ($cgi->param('show_missing_including_matches'))
    {
        &format_missing_including_matches($fig,$cgi,$html,$subsystem);
    }
    if ($cgi->param('show_missing_including_matches_in_ss'))
    {
        &format_missing_including_matches_in_ss($fig,$cgi,$html,$subsystem);
    }
     

    if ($cgi->param('check_assignments'))
    {
        &format_check_assignments($fig,$cgi,$html,$subsystem);
    }

    if ($cgi->param('show_dups'))
    {
        &format_dups($fig,$cgi,$html,$subsystem);
    }

    if ($cgi->param('show_coupled'))
    {
        &format_coupled($fig,$cgi,$html,$subsystem,"careful");
    }
    elsif ($cgi->param('show_coupled_fast'))
    {
        &format_coupled($fig,$cgi,$html,$subsystem,"fast");
    }

    my $col;
    if ($col = $cgi->param('col_to_annotate'))
    {
        &annotate_column($fig,$cgi,$html,$col,$subsystem);
    }

    if ($cgi->param('ma_data_diagram_action'))
    {
	&paint_ma_data($fig,$cgi,$ssa,$subsystem);
        &make_link_to_painted_diagram($fig,$cgi,$html);
    }

    if ($cgi->param('paint_diagram_role_by_attribute_value'))
    {
        if ($cgi->param('paint_diagram_role_by_attribute_value')){
            my $diagram_name = $cgi->param('diagram_to_color');
	    my $possible_roles_to_color = &find_roles_to_color($fig,$cgi,$html,$subsystem);
	    &color_diagram_role_by_av($fig,$cgi,$ssa,$subsystem,$possible_roles_to_color,$diagram_name);
	    &make_link_to_painted_diagram($fig,$cgi,$html);
        }
    }

    if ( $time_it )                  ## time ##
    {                                ## time ##
        push @times, scalar time();  ## time ##
        push @$html, "<br>dT = @{[$times[-1]-$times[-2]]}, T = @{[$times[-1]-$times[0]]}<br>";  ## time ##
    }                                ## time ##
}

########
#  Displays the start,end and map relation table to kegg
#  Kevin Formsma 2006 Hope College
#
sub format_kegg_info 
{
    my ($fig,$cgi,$html,$subsystem,$can_alter,$active_genome_list) = @_;
    push(@$html, $cgi->hr, $cgi->h2("KEGG Contextual Information"));

    my @kegg_genomes = sort { lc $a->[1] cmp lc $b->[1] } map { [ $_->[0], "$_->[1] [$_->[0]]" ] } @$active_genome_list;
    unshift @kegg_genomes, [ '', 'All' ];

    push(@$html, "<p>Find matching KEGG maps for:&nbsp;&nbsp;",
	 $cgi->popup_menu( -name   => 'kegg_genome',
			   -values => [ map {   $_->[0]            } @kegg_genomes ],
			   -labels => { map { ( $_->[0], $_->[1] ) } @kegg_genomes }
			   )
	 );
    
    push(@$html, 
	 $cgi->submit(-name => 'show_KGML', -label => 'All roles'), 
	 "&nbsp;",
	 $cgi->submit(-name => 'show_KGML', -label => 'Active subset roles'), 
	 $cgi->br
	 );

    if ($cgi->param('show_KGML'))
    {	
	my %reactions = $subsystem->get_hope_reactions;
	my @roles = ();
	my $kegg_genome = $cgi->param('kegg_genome');
	my $active_subsetC = ($cgi->param('active_subsetC') or $subsystem->get_active_subsetC );
	my @subsetC = $subsystem->get_subsetC_roles($active_subsetC);
	my %activeC = map { $_ => 1 } @subsetC;

	foreach my $role ($subsystem->get_roles)
	{
	    if (($cgi->param('show_KGML') eq "Active subset roles" && ! defined($activeC{$role})) ||
		($kegg_genome ne "" && $subsystem->get_pegs_from_cell($kegg_genome,$role) == 0))
	    {
		delete $reactions{$role};
	    }
	    else
	    {
		push @roles, $role;
	    }
	}

	my $kgml = new KGMLData;
	push(@$html, "<p>");
	show_matching_pathways($kgml,\@roles,$cgi,$html, \%reactions);
    }

    push(@$html, "<p>Go to <a href=\"javascript:void(0)\"onclick=\"window.open('hope_tools.cgi','','height=600,width=800,scrollbars=yes,status=yes,resizable=yes')\">the scenario tools<\/a>");;

    my @hope_scenario_names = $subsystem->get_hope_scenario_names;

    foreach my $scenario_name (sort @hope_scenario_names)
    {
	my @hope_input_compounds = $subsystem->get_hope_input_compounds($scenario_name);
	my @hope_output_compounds = $subsystem->get_hope_output_compounds($scenario_name);
	my @hope_mapIDs = $subsystem->get_hope_map_ids($scenario_name);
	my @hope_additional_reactions = $subsystem->get_hope_additional_reactions($scenario_name);
	my @hope_ignore_reactions = $subsystem->get_hope_ignore_reactions($scenario_name);
	
	my $display_name = $scenario_name;
	$display_name =~ s/_/ /g;
	push(@$html, "<p><b><font size=+1>Scenario: $display_name</font></b>");

	if($can_alter)
	{
	    my $scenarioName = $cgi->textfield(-name => $scenario_name."_Name", -size => 30, -value => "", -override => 1);
	    push(@$html, "&nbsp;&nbsp;(Change name:&nbsp;&nbsp;", $scenarioName, ")&nbsp;&nbsp;");
	    push(@$html, $cgi->submit(-name => $scenario_name."_Delete", -label => "Delete scenario"), "<p>");
	}
	else
	{
	    push(@$html, "<p>");
	}	

	my $edit_kegg_col = '';
	if ($can_alter)
	{
	    $edit_kegg_col = "<th>Edit KEGG IDs (comma-separated list, parentheses to group)</th>";
	}
	push(@$html,"<table border=1><tr><th>&nbsp;</th><th>KEGG IDs</th>$edit_kegg_col</tr><tr><td><b>Input Compounds<b></td>");
	my @compound_info;

	foreach my $cpd (@hope_input_compounds)
	{
	    my @compound_names = $fig->names_of_compound($cpd);
	    my $name = (scalar @compound_names > 0) ? "$compound_names[0]" : "";
	    push @compound_info, &HTML::compound_link($cpd)." ".$name;
	}

	my $input_string = join("<br>", @compound_info);
	push(@$html,"<td>$input_string</td>");	
	
	if($can_alter)
	{
	    my $hopeInputCompounds  = $cgi->textfield(-name => $scenario_name."_InputCompounds", -size => 50, -value => "", -override => 1);
	    push(@$html,"<td>$hopeInputCompounds</td>");
	}

	push(@$html,"</tr>");
	my @compound_info;

	foreach my $cpd_list (@hope_output_compounds)
	{
	    my @inner_compound_info;

	    foreach my $cpd (@$cpd_list)
	    {
		my @compound_names = $fig->names_of_compound($cpd); 
		my $name = (scalar @compound_names > 0) ? "$compound_names[0]" : ""; 
		push @inner_compound_info, &HTML::compound_link($cpd)." ".$name;
	    }
	    
	    push @compound_info, join ", ", @inner_compound_info;
	}

	my $output_string = join("<br>", @compound_info);
	push(@$html,"<tr><td><b>Output Compounds</b></td><td>$output_string</td>");
	
	if($can_alter)
	{
	    my $hopeOutputCompounds  = $cgi->textfield(-name => $scenario_name."_OutputCompounds", -size => 50, -value => "", -override => 1);
	    push(@$html,"<td>$hopeOutputCompounds</td>");    
	}

	push(@$html,"</tr>");
	push(@$html,"<tr><td><b>Pathway Maps</b></td>");

	my %hope_reactions = $subsystem->get_hope_reactions;
	my %reaction_list;
	my @roles = $subsystem->get_roles;
	my %roles;
	map { $roles{$_} = 1 } @roles;

	foreach my $role (keys %hope_reactions)
	{
	    if (defined $roles{$role})
	    {
		map { $reaction_list{$_} = 1 } @{$hope_reactions{$role}};
	    }
	}
	map { $reaction_list{$_} = 1 } @hope_additional_reactions;
	map { delete $reaction_list{$_} } @hope_ignore_reactions;

	my @map_info;

	foreach my $mapid (@hope_mapIDs)
	{
	    my $name = $fig->map_name("map".$mapid);
	    push @map_info, &HTML::reaction_map_link($mapid, keys %reaction_list)." ".$name;
	}

	my $ids_string = join("<br>", @map_info);
	push(@$html,"<td>$ids_string</td>");
	
	if($can_alter)
	{
	    my $hopeMapIDs  = $cgi->textfield(-name => $scenario_name."_MapIDs", -size => 50, -value => "", -override => 1);
	    push(@$html,"<td>$hopeMapIDs</td>");
	}	
	push(@$html,"</tr>");

	push(@$html,"<tr><td><b>Additional Reactions</b></td>");
	my $add_rxns = join(", ", map { &HTML::reaction_link($_) } @hope_additional_reactions);
	push(@$html, "<td>$add_rxns</td>");

	if($can_alter)
	{
	    my $hopeAddRxns  = $cgi->textfield(-name => $scenario_name."_AddRxns", -size => 50, -value => "", -override => 1);
	    push(@$html,"<td>$hopeAddRxns</td>");
	}	
	push(@$html,"</tr>");

	push(@$html,"<tr><td><b>Ignore Reactions</b></td>");
	my $ignore_rxns = join(", ", map { &HTML::reaction_link($_) } @hope_ignore_reactions);
	push(@$html, "<td>$ignore_rxns</td>");

	if($can_alter)
	{
	    my $hopeIgnoreRxns  = $cgi->textfield(-name => $scenario_name."_IgnoreRxns", -size => 50, -value => "", -override => 1);
	    push(@$html,"<td>$hopeIgnoreRxns</td>");
	}	
	push(@$html,"</tr>");

	push(@$html,"</table>");

	my $ss_name = $subsystem->get_name;
	push(@$html, 
	     "Find reaction paths for&nbsp&nbsp");
	push(@$html, 
	     $cgi->popup_menu( -name   => "${scenario_name}_genome",
			       -values => [ map {   $_->[0]            } @kegg_genomes ],
			       -labels => { map { ( $_->[0], $_->[1] ) } @kegg_genomes }
			       ),
	     $cgi->button(-name => "${scenario_name}_One_button", -label => 'Find One Path', -onClick => "window.open('find_reaction_paths.cgi?one_or_all=1&ssa=$ss_name&scenario_name=$scenario_name&genome='+MainForm.${scenario_name}_genome[MainForm.${scenario_name}_genome.selectedIndex].value,'$ss_name (reactions for $scenario_name) '+MainForm.${scenario_name}_genome.selectedIndex,'height=640,width=800,scrollbars=yes,toolbar=yes,status=yes,resizable=yes')"), 
	     $cgi->button(-name => "${scenario_name}_All_button", -label => 'Find All Paths', -onClick => "window.open('find_reaction_paths.cgi?one_or_all=0&ssa=$ss_name&scenario_name=$scenario_name&genome='+MainForm.${scenario_name}_genome[MainForm.${scenario_name}_genome.selectedIndex].value,'$ss_name (reactions for $scenario_name) '+MainForm.${scenario_name}_genome.selectedIndex,'height=640,width=800,scrollbars=yes,toolbar=yes,status=yes,resizable=yes')"), 
	     $cgi->br,
	     "<p>"
	     );
    }

    if($can_alter)
    {
	my $scenarioName = $cgi->textfield(-name => "newscenario_Name", -size => 50, -value => "", -override => 1);
	push(@$html, "<p>New scenario name:&nbsp;&nbsp;", $scenarioName, "<p>");
    }

    push(@$html, $cgi->hr);
}





###show_matching_pathways###
#
# Input: KGMLData Object, Subsystem Object, CGI objectm HTML data array
#
# Output: HTML formating displaying the results of the functin get_matching_pathways
############################
sub show_matching_pathways
{	
    my($kgml,$roles,$cgi,$html,$hope_reactions) = @_;
    my $ssa  = $cgi->param('ssa_name');
    #get the subsystem EC numbers
    my @ecs = $kgml->roles_to_ec(@{$roles});
    my @rns;
    
    if (defined $hope_reactions)
    {
	my %hope_rns = %{$hope_reactions};
	foreach my $role (keys %hope_rns)
	{
	    push @rns, @{$hope_rns{$role}};
	}
    }
    
    #if defined, lets continue, else print error
    if(@ecs)
    {
	    #get a list of the pathways with matches, their links, and how many EC's matched.
	my $matching_array;
	eval {$matching_array = $kgml->get_matching_pathways($FIG_Config::kgml_dir."/map/",\@ecs,\@rns)};
	if($@ || !defined $matching_array)
	{
	    push(@$html, "No Results Found or Error: $@");
	}
	else{
	    foreach my $entry (@$matching_array){
		
		push(@$html,"$entry->[1] => ","<a href=\"$entry->[2]\">EC numbers in map $entry->[0]</a> and <a href=\"$entry->[3]\">Hope Reactions in map $entry->[0]</a>  Count=$entry->[4]",$cgi->br,$cgi->br);					
	    }
	}		
    }
    else
    {
	push(@$html,"No matching EC numbers or Hope Reactions.");
    }
}


#-----------------------------------------------------------------------------
#  Selection list of complete genomes not in spreadsheet:
#-----------------------------------------------------------------------------

sub format_extend_with {
    my( $fig, $cgi, $html, $subsystem ) = @_;

    my %genomes = map { $_ => 1 } $subsystem->get_genomes();

    #
    #  Use $fig->genomes( complete, restricted, domain ) to get org list:
    #
    my $req_comp = $cgi->param( 'complete' ) || 'Only "complete"';
    my $complete = ( $req_comp =~ /^all$/i ) ? undef : "complete";

    #  What domains are to be displayed in the genome picker?
    #  These are the canonical domain names defined in compute_genome_counts
    #  and entered in the DBMS:

    my %maindomain = ( Archaea               => 'A',
                       Bacteria              => 'B',
                       Eukaryota             => 'E',
                       Plasmid               => 'P',
                       Virus                 => 'V',
                      'Environmental Sample' => 'M',  # Metagenome
                       unknown               => 'U'
                     );

    my %label = ( Archaea               => 'Archaea [A]',
                  Bacteria              => 'Bacteria [B]',
                  Eukaryota             => 'Eucarya [E]',
                  Plasmid               => 'Plasmids [P]',
                  Virus                 => 'Viruses [V]',
                 'Environmental Sample' => 'Environmental (metagenomes) [M]',
                  unknown               => 'unknown [U]'
                );

    #  Currently, compute_genome_counts marks everything that is not Archae,
    #  Bacteria or Eukcayra to not complete.  So, the completeness status must
    #  be ignored on the others.

    my %honor_complete = ( Archaea => 1, Bacteria => 1, Eukaryota => 1 );

    #  Requested domains or default:

    my @picker_domains = grep { $maindomain{ $_ } }
                         $cgi->param( 'picker_domains' );
    if ( ! @picker_domains ) { @picker_domains = qw( Archaea Bacteria Eukaryota ) }

    my %picker_domains = map { ( $_ => 1 ) } @picker_domains;

    #  Build the domain selection checkboxes:

    my @domain_checkboxes = ();
    my %domain_abbrev = reverse %maindomain;
    foreach ( map { $domain_abbrev{ $_ } } qw( A B E P V M U ) )
    {
        push @domain_checkboxes, $cgi->checkbox( -name     => 'picker_domains',
                                                 -value    => $_,
                                                 -checked  => ( $picker_domains{ $_ } ? 1 : 0 ),
                                                 -label    => $label{ $_ },
                                                 -override => 1
                                               )
    }

    #  Assemble the genome list for the picker.  This could be optimized for
    #  some special cases, but it is far from rate limiting.  Most of the time
    #  is looking up the name and domain, not the call to genomes().
    #  Each org is represented as [ id, genus_species, domain ]

    my @orgs = ();
    foreach my $domain ( @picker_domains )
    {
        push @orgs, map { [ $_, $fig->genus_species_domain( $_ ) ] }
                    grep { ! $genomes{ $_ } }
                    $fig->genomes( $complete && $honor_complete{ $domain }, undef, $domain )
    }

    #
    #  Put it in the order requested by the user:
    #
    my $pick_order = $cgi->param('pick_order') || 'Alphabetic';
    if ( $pick_order eq "Phylogenetic" )
    {
        @orgs = sort { $a->[-1] cmp $b->[-1] }
                map  { push @$_, lc $fig->taxonomy_of( $_->[0] ); $_ }
                @orgs;
    }
    elsif ( $pick_order eq "Genome ID" )
    {
        @orgs = sort { $a->[-1]->[0] <=> $b->[-1]->[0] || $a->[-1]->[1] <=> $b->[-1]->[1] }
                map  { push @$_, [ split /\./, $_->[0] ]; $_ }
                @orgs;
    }
    else
    {
        $pick_order = 'Alphabetic';
        @orgs = sort { $a->[-1] cmp $b->[-1] }
                map  { push @$_, lc $_->[1]; $_ }
                @orgs;
    }

    #  Build the displayed name:

    @orgs = map { "$_->[1] [$maindomain{$_->[2]}] ($_->[0])" } @orgs;

    #
    #  Radio buttons to let the user choose the order they want for the list:
    #
    my @order_opt = $cgi->radio_group( -name     => 'pick_order',
                                       -values   => [ 'Alphabetic', 'Phylogenetic', 'Genome ID' ],
                                       -default  => $pick_order,
                                       -override => 1
                                     );

    #
    #  Radio buttons to let the user choose to include incomplete genomes:
    #
    my @complete = $cgi->radio_group( -name     => 'complete',
                                      -default  => $req_comp,
                                      -override => 1,
                                      -values   => [ 'All', 'Only "complete"' ]
                        );

    #
    #  Display the pick list, and options:
    #
    my @roles = $subsystem->get_roles;
    push( @$html, $cgi->h2('Pick Genomes to Extend with'), "\n",
                  "<TABLE>\n",
                  "  <TR VAlign=top>\n",
                  "    <TD>",
                  $cgi->scrolling_list( -name     => 'new_genome',
                                        -values   => [ @orgs ],
                                        -size     => 10,
                                        -multiple => 1
                                      ),
                  "    </TD>\n",

                  "    <TD>",
                  join( "<BR>\n", "<b>Order of selection list:</b>", @order_opt,
                                  "<b>Completeness?</b>", @complete
                      ), "\n",
                  "    </TD>\n",

                  "    <TD>&nbsp;&nbsp;&nbsp;</TD>\n",

                  "    <TD>\n",
                  join( "<BR>\n", "<B>Include in selection list:</B>", @domain_checkboxes ), "\n",
                  "    </TD>\n",

                  "  </TR>\n",
                  "</TABLE>\n",

                  $cgi->p("Add a specific group of genomes:"), 
                  $cgi->checkbox_group(  -name=>"moregenomes", 
                                         -values=>["NMPDR", "BRC", "Cyanobacteria", "Higher Plants", "Photosynthetic Eukaryotes", "Anoxygenic Phototrophs", "Hundred by a hundred", "Phages"],
                                      )
        );

    if ( $time_it )                  ## time ##
    {                                ## time ##
        push @times, scalar time();  ## time ##
        push @$html, "<br>dT = @{[$times[-1]-$times[-2]]}, T = @{[$times[-1]-$times[0]]}<br>";  ## time ##
    }                                ## time ##

    push @$html, $cgi->hr;
}

#
# Write out information about this subsystem as javascript
# data structures. Used for the  diagram coloring currently.
#
sub format_js_data
{
    my($fig,$cgi,$html,$subsystem,$can_alter) = @_;

    push(@$html, qq(<script language="JavaScript">\n),
         "subsystemInfo = {\n");

        my $first = 1;
    for my $g ($subsystem->get_genomes())
    {
        my $txt = '';
        #
        # Determine which roles this genome has.
        #
        if (!$first)
        {
            $txt .= ", ";
        }
        else
        {
            $first = 0;
        }

        $txt .= "'$g': [";

        my $gi = $subsystem->get_genome_index($g);

        my $row = $subsystem->get_row($gi);

        my @r;
        for (my $ri = 0; $ri < @$row; $ri++)
        {
            my $cell = $row->[$ri];
            if ($#$cell > -1)
            {
                push(@r, "'" . $subsystem->get_role_abbr($ri) . "'");
            }
        }

        $txt .= join(", ", @r);
        $txt .= "]\n";
        push(@$html, $txt);
    }
    push(@$html, "};\n");
    push(@$html, "</script>\n");
}

sub format_roles {
    my($fig,$cgi,$html,$subsystem,$can_alter) = @_;
    my($i);

    my @roles = $subsystem->get_roles;
    my @genomes = $subsystem->get_genomes;
    my $sub_dir = $subsystem->get_dir;

    my $reactions = $subsystem->get_reactions;
    my %hope_reactions = $subsystem->get_hope_reactions;
    my %hope_reaction_notes = $subsystem->get_hope_reaction_notes;
    my %hope_reaction_links = $subsystem->get_hope_reaction_links;

    my $n = 1;
    my $col_hdrs = ["Column","Abbrev","Functional Role", "Num Genomes"];

    if ($can_alter)
    { 
#prehope#        push(@$col_hdrs,"KEGG Reactions");
#prehope#        push(@$col_hdrs,"Edit Reactions");
        push(@$col_hdrs,"Role Reactions");
        push(@$col_hdrs,"Edit Role Reactions");
        push(@$col_hdrs,"Hope Reactions");
#        push(@$col_hdrs,"Edit Hope Reactions");
        push(@$col_hdrs,"Hope Reaction Notes");
#        push(@$col_hdrs,"Hope_Reaction_Links_Hope_Reaction_Links_Hope_Reaction_Links");
    }
    else
    {
	if ($reactions)
	{
	    push(@$col_hdrs,"Role Reactions");
	}
	if (%hope_reactions)
	{
	    push(@$col_hdrs,"Hope Reactions");
	    push(@$col_hdrs,"Hope Reaction Notes");
	}
    }


    my $tab = [];

    &format_existing_roles($fig,$cgi,$html,$subsystem,$tab,\$n,$can_alter,$reactions,\%hope_reactions,
			   \%hope_reaction_notes,\%hope_reaction_links,\@roles,\@genomes);
    if ($cgi->param('can_alter'))
    {
        for ($i=0; ($i < 5); $i++)
        {
            &format_role($fig,$cgi,$html,$subsystem,$tab,$n,"",$can_alter,undef);
            $n++;
        }
    }
    my %options; if ($cgi->param("create_excel")) {%options=(excelfile=>$cgi->param('ssa_name'), no_excel_link=>1)}
    push(@$html,&HTML::make_table($col_hdrs,$tab,"Functional Roles", %options),
                $cgi->hr
         );

    if ( $time_it )                  ## time ##
    {                                ## time ##
        push @times, scalar time();  ## time ##
        push @$html, "<br>dT = @{[$times[-1]-$times[-2]]}, T = @{[$times[-1]-$times[0]]}<br>";  ## time ##
    }                                ## time ##
}

sub format_existing_roles {
    my($fig,$cgi,$html,$subsystem,$tab,$nP,$can_alter,$reactions,$hope_reactions,$hope_reaction_notes,$hope_reaction_links,$roles,$genomes) = @_;
    my($role);

    foreach $role (@$roles)
    {
        &format_role($fig,$cgi,$html,$subsystem,$tab,$$nP,$role,$can_alter,$reactions,$hope_reactions,$hope_reaction_notes,$hope_reaction_links,$genomes);
        $$nP++;
    }
}

sub format_role {
    my($fig,$cgi,$html,$subsystem,$tab,$n,$role,$can_alter,$reactions,$hope_reactions,$hope_reaction_notes,$hope_reaction_links,$genomes) = @_;
    my($abbrev,$reactT,$hopeReactT);

    my $react = $reactions ? join(", ", map { &HTML::reaction_link($_) } @{$reactions->{$role}}) : "";
    my $hope_react = $hope_reactions ? join(", ", map { &HTML::reaction_link($_) } @{$hope_reactions->{$role}}) : "";
    my $hope_reaction_note = $hope_reaction_notes ? $hope_reaction_notes->{$role} : "";
    my $hope_reaction_link = $hope_reaction_links ? $hope_reaction_links->{$role} : "";
    $hope_reaction_link =~ s/;/<br>/g;

    my %reaction_links;
    while ($hope_reaction_link =~ /(R\d\d\d\d\d)/g)
    {
	$reaction_links{$1} = &HTML::reaction_link($1);
    }

    foreach my $reaction (keys %reaction_links)
    {
	$hope_reaction_link =~ s/$reaction/$reaction_links{$reaction}/g;
    }

    $hope_reaction_link =~ s/(\w_\w+):(\w+(\.\d)?)/<a href=\"javascript:void(0)\"onclick=\"window.open('get_model_reactions.cgi?org=$1&gene=$2','$&','height=600,width=800,scrollbars=yes,status=yes,resizable=yes')\">$&<\/a>/g;

    $abbrev = $role ? $subsystem->get_role_abbr($subsystem->get_role_index($role)) : "";

    my($posT,$abbrevT,$roleT,$hopeNoteT);
    if ($can_alter)
    {
        $posT    = $cgi->textfield(-name => "posR$n", -size => 3, -value => $n, -override => 1);
        $abbrevT = $cgi->textfield(-name => "abbrev$n", -size => 7, -value => $abbrev, -override => 1);
        $roleT   = $cgi->textfield(-name => "role$n", -size => 60, -value => $role, -override => 1);
        $reactT  = $cgi->textfield(-name => "react$n", -size => 20, -value => "", -override => 1);
        $hopeReactT  = $cgi->textfield(-name => "hopeReact$n", -size => 20, -value => "", -override => 1);
        $hopeNoteT   = $cgi->textarea(-name => "hopeNote$n", -columns => 60, -rows => 3, -value => $hope_reaction_note, -override => 1);
    }
    else
    {
        push(@$html,$cgi->hidden(-name => "posR$n", -value => $n, -override => 1),
                    $cgi->hidden(-name => "abbrev$n", -value => $abbrev, -override => 1),
                    $cgi->hidden(-name => "role$n", -value => $role, -override => 1));
        $posT = $n;
        $abbrevT = $abbrev;
        $roleT = $role;
    }

    my $ngenomes = 0;
    for (my $genomeIdx=0; $genomeIdx <= $#$genomes; $genomeIdx++) {
    	if (scalar($subsystem->get_pegs_from_cell($genomeIdx, $role)) > 0) {$ngenomes++}
    }


    #
    # Wrap the first element in the table with a <A NAME="role_rolename"> tag
    # so we can zing to it from elsewhere. We remove any non-alphanumeric
    # chars in the role name.
    #
    # Is there a reason for doing this ... it is not used. 

    my $posT_html;
    {
        my $rn = $role;
        $rn =~ s/[ \/]/_/g;
        $rn =~ s/\W//g;

        $posT_html = "<a name=\"$rn\">$posT</a>";
    }
    
    #my $row = [$posT_html,$abbrevT,$roleT];
    my $row = [$posT,$abbrevT,$roleT,$ngenomes];
    if ($can_alter)
    {
        push(@$row,$react);
        push(@$row,$reactT);
        push(@$row,$hope_react);
#        push(@$row,$hopeReactT);
        push(@$row,$hopeNoteT);
#	push(@$row,$hope_reaction_link);
    }
    else
    {
	if ($reactions)
	{
	    push(@$row,$react);
	}
	if ($hope_reactions)
	{
	    push(@$row,$hope_react);
	    push(@$row,$hope_reaction_note);
	}
    }
    push(@$tab,$row);

    if ($cgi->param('check_problems'))
    {
        my @roles    = grep { $_->[0] ne $role } &gene_functions_in_col($fig,$role,$subsystem);
        my($x,$peg);
        foreach $x (@roles)
        {
            push(@$tab,["","",$x->[0]]);
            push(@$tab,["","",join(",",map { &HTML::fid_link($cgi,$_) } @{$x->[1]})]);
        }
    }
}

sub gene_functions_in_col {
    my($fig,$role,$subsystem) = @_;
    my(%roles,$peg,$func);
   
   
    # RAE this is dying if $subsystem->get_col($subsystem->get_role_index($role) + 1) is not defined
    # it is also not returning the right answer, so we need to fix it.
    # I am not sure why this is incremented by one here (see the note) because it is not right
    # and if you don't increment it by one it is right.
    
                                            # incr by 1 to get col indexed from 1 (not 0)
    #my @pegs = map { @$_ } @{$subsystem->get_col($subsystem->get_role_index($role) + 1)}; 
    
    return undef unless ($role); # this takes care of one error
    my $col_role=$subsystem->get_col($subsystem->get_role_index($role));
    return undef unless (defined $col_role);
    my @pegs = map { @$_ } @$col_role;

    foreach $peg (@pegs)
    {
        if ($func = $fig->function_of($peg))
        {
            push(@{$roles{$func}},$peg);
        }
    }
    return map { [$_,$roles{$_}] } sort keys(%roles);
}

sub format_subsets {
    my($fig,$cgi,$html,$subsystem,$can_alter) = @_;

    &format_subsetsC($fig,$cgi,$html,$subsystem,$can_alter);
    &format_subsetsR($fig,$cgi,$html,$subsystem,$can_alter);
}

sub format_subsetsC {
    my($fig,$cgi,$html,$subsystem,$can_alter) = @_;

    my $col_hdrs = ["Subset","Includes These Roles"];
    my $tab = [];

    my $n = 1;
    &format_existing_subsetsC($cgi,$html,$subsystem,$tab,\$n,$can_alter);

    if ($can_alter)
    {
        my $i;
        for ($i=0; ($i < 5); $i++)
        {
            &format_subsetC($cgi,$html,$subsystem,$tab,$n,"");
            $n++;
        }
    }

    my %options; if ($cgi->param("create_excel")) {%options=(excelfile=>$cgi->param('ssa_name'), no_excel_link=>1)}
    push(@$html,&HTML::make_table($col_hdrs,$tab,"Subsets of Roles", %options),
                $cgi->hr
         );

    my @subset_names = sort $subsystem->get_subset_namesC;
    if (@subset_names > 1)
    {
        my $active_subsetC = ($cgi->param('active_subsetC') or $subsystem->get_active_subsetC );
        push(@$html,$cgi->scrolling_list(-name => 'active_subsetC',
                                         -values => [@subset_names],
                                         -default => $active_subsetC
                                         ),
                    $cgi->br, "\n",
             );
    }
    else
    {
        push(@$html,$cgi->hidden(-name => 'active_subsetC', -value => 'All', -override => 1));
    }

    if ( $time_it )                  ## time ##
    {                                ## time ##
        push @times, scalar time();  ## time ##
        push @$html, "<br>dT = @{[$times[-1]-$times[-2]]}, T = @{[$times[-1]-$times[0]]}<br>";  ## time ##
    }                                ## time ##
}

sub format_subsetsR {
    my($fig,$cgi,$html,$subsystem,$can_alter) = @_;
    my($i);

    my $link = &tree_link;
    push(@$html, $cgi->h2("Limit display"), $link,$cgi->br);

    #
    # Default to showing All unless you're a curator.
    #

    my $active_subsetR;
    
    my $default_activeSubsetR = $can_alter ? $subsystem->get_active_subsetR  : "All";

    $active_subsetR = ($cgi->param('active_subsetR') or $default_activeSubsetR);

    my @tmp = grep { $_ ne "All" } sort $subsystem->get_subset_namesR;

# RAE: provide some alternative choices, and a little explantion
    my %options=(
            "higher_plants"   => "Higher Plants",
            "eukaryotic_ps"   => "Photosynthetic Eukaryotes",
            "nonoxygenic_ps"  => "Anoxygenic Phototrophs",
            "hundred_hundred" => "Hundred by a hundred",
            "functional_coupling_paper" => "Functional Coupling Paper",
	    "cyano_or_plant" => "Cyanos OR Plants",
            "ecoli_essentiality_paper" => "E. coli Essentiality Paper",
	    "has_essentiality_data"	=> "Genomes with essentiality data",
            "" =>  "All",
            );
    
    push(@$html,
        $cgi->p("Limit display of the the genomes in the table based on phylogeny or one of the preselected groups:"),
        "\n<table><tr><td>",
        $cgi->scrolling_list(-name => 'active_subsetR',
                                     -values => ["All",@tmp],
                                     -default => $active_subsetR,
                                     -size => 5
                                     ),
        "</td><td>\n",
        $cgi->radio_group(-name=>"active_key", -values=>[keys %options], -labels=>\%options, -linebreak=>'true', -default=>"", columns=>4),
        "</td></tr>\n</table>",
         );

    if ( $time_it )                  ## time ##
    {                                ## time ##
        push @times, scalar time();  ## time ##
        push @$html, "<br>dT = @{[$times[-1]-$times[-2]]}, T = @{[$times[-1]-$times[0]]}<br>";  ## time ##
    }                                ## time ##
}

sub format_existing_subsetsC {
    my($cgi,$html,$subsystem,$tab,$nP,$can_alter) = @_;
    my($nameCS);

    foreach $nameCS (sort $subsystem->get_subset_namesC)
    {
        if ($nameCS !~ /all/i)
        {
            &format_subsetC($cgi,$html,$subsystem,$tab,$$nP,$nameCS);
            $$nP++;
        }
    }
}

sub format_subsetC {
    my($cgi,$html,$subsystem,$tab,$n,$nameCS) = @_;

    if ($nameCS ne "All")
    {
        my $subset = $nameCS ? join(",",map { $subsystem->get_role_index($_) + 1 } $subsystem->get_subsetC_roles($nameCS)) : "";

        $nameCS = $subset ? $nameCS : "";

        my($posT,$subsetT);

        $posT    = $cgi->textfield(-name => "nameCS$n", -size => 30, -value => $nameCS, -override => 1);
        $subsetT = $cgi->textfield(-name => "subsetC$n", -size => 80, -value => $subset, -override => 1);
        push(@$tab,[$posT,$subsetT]);
    }
}


#
# Handle changes to diagrams.
#

sub handle_diagram_changes
{
    my($fig, $subsystem, $cgi, $html) = @_;
    my $changed;
    my $sub_name = $subsystem->get_name();

    return unless $cgi->param("diagram_action");

    my @actions = grep { /^diagram_/ } $cgi->param();

    for my $action (@actions)
    {
        my $value = $cgi->param($action);
        if ($action =~ /^diagram_delete_(\S+)/ and $value eq "on")
        {
            warn "Delete diagram $sub_name $1\n";
            $subsystem->delete_diagram($1);
            $changed++;
        }
        elsif ($action =~ /^diagram_rename_(\S+)/ and $value ne "")
        {
            warn "Rename diagram $sub_name $1 to $value\n";
            $subsystem->rename_diagram($1, $value);
            $changed++;
        }
        elsif ($action =~ /^diagram_new_image_(\S+)/ and $value ne '')
        {
            my $fh = $cgi->upload($action);
            warn "Upload new image $fh $value for diagram $sub_name $1\n";
            $subsystem->upload_new_image($1, $cgi->upload($action));
            $changed++;
        }
        elsif ($action =~ /^diagram_new_html_(\S+)/ and $value ne '')
        {
            my $fh = $cgi->upload($action);
            warn "Upload new html $fh $value for diagram $sub_name $1\n";
            $subsystem->upload_new_html($1, $cgi->upload($action));
            $changed++;
        }
            
    }

    my $fh = $cgi->upload("diagram_image_file");
    my $html_fh = $cgi->upload("diagram_html_file");

    if ($fh)
    {
        my $name = $cgi->param("diagram_new_name");
        
        warn "Create new diagram $fh $html_fh name=$name\n";
        $subsystem->create_new_diagram($fh, $html_fh, $name);
        $changed++;
    }

    $subsystem->incr_version() if $changed;
}

#
# Format the list of diagrams that a subsystem has.
#

sub format_diagrams
{
    my($fig, $cgi, $html, $subsystem, $can_alter) = @_;

    my @diagrams = $subsystem->get_diagrams();
    my @diagram_names;

    if (@diagrams or $can_alter)
    {
        push(@$html, $cgi->hr, $cgi->h2("Subsystem Diagrams"));
    }

    if ( $time_it )                  ## time ##
    {                                ## time ##
        push @times, scalar time();  ## time ##
        push @$html, "<br>dT = @{[$times[-1]-$times[-2]]}, T = @{[$times[-1]-$times[0]]}<br>";  ## time ##
    }                                ## time ##

    if (@diagrams)
    {
        my @hdr = ("Diagram Name");

        if ($can_alter)
        {
            push(@hdr, "Delete", "Rename", "New image", "New html");
        }
        
        my @tbl;
        for my $dent (@diagrams)
        {
            my($id, $name, $link) = @$dent;
            push(@diagram_names,$name);
            
	    my @row;

            my $js = "showDiagram('$link', '$id'); return false;";

	    if ($subsystem->is_new_diagram($id)) {
		$link = $subsystem->get_link_for_new_diagram($id);
		push(@row, qq(<a href="$link" target="_new_diagram">$name</a>));
            } 
            else {
               push(@row, qq(<a href="$link" onclick="$js" target="show_ss_diagram_$id">$name</a>));
	    }

            if ($can_alter)
            {
                push(@row, $cgi->checkbox(-name => "diagram_delete_$id", -label => "",
                                          -value => undef,
                                          -override => 1));
                push(@row, $cgi->textfield(-name => "diagram_rename_$id",
                                           -value => "",
                                           -override => 1));
                push(@row, $cgi->filefield(-name => "diagram_new_image_$id",
                                           -value => "",
                                           -override => 1,
                                           -size => 30));
                push(@row, $cgi->filefield(-name => "diagram_new_html_$id",
                                           -value => "",
                                           -override => 1,
                                           -size => 30));
            }
            
            push(@tbl, \@row);
        }
        push(@$html, &HTML::make_table(\@hdr, \@tbl));
    }

   
        my @tbl;
	my @tbl_ma;
	my @tbl_attribute;
        push(@tbl, ["Diagram name:", $cgi->textfield(-name => "diagram_new_name",
                                                     -value => "",
                                                     -override => 1,
                                                     -size => 30)]);
        push(@tbl, ["Diagram image file:", $cgi->filefield(-name => "diagram_image_file",
                                                           -size => 50)]);
        push(@tbl, ["Diagram html file:", $cgi->filefield(-name => "diagram_html_file",
                                                           -size => 50)]);
        push(@$html, $cgi->h3("Upload a new diagram"));
        push(@$html, &HTML::make_table(undef, \@tbl));
        push(@$html, $cgi->submit(-name => 'diagram_action',
                                  -label => 'Process diagram actions'));
        push(@tbl_ma, ["Genome ID:", $cgi->textfield(-name => "ma_data_genome_id",
						     -value => "",
                                                     -override => 1,
                                                     -size => 30)]);
	push(@tbl_ma, ["Image File Width:", $cgi->textfield(-name => "image_file_width",
                                                     -value => "",
                                                     -override => 1,
                                                     -size => 30)]);
        
	push(@tbl_ma, ["Image File Height:", $cgi->textfield(-name => "image_file_height",
						     -value => "",
                                                     -override => 1,
                                                     -size => 30)]);
        push(@tbl_ma, ["Microarray data file:", $cgi->filefield(-name => "ma_data_file",
                                                           -size => 50)]);
        push(@$html, $cgi->h3("View microarray data on diagram"));
        push(@$html, &HTML::make_table(undef, \@tbl_ma));
        
        push(@$html, $cgi->submit(-name => 'ma_data_diagram_action',
                                  -label => 'View microarray data on diagram'));

        my @select_keys = ( undef, sort { uc($a) cmp uc($b) }
                                   grep { /(Essential|fitness)/i }
                                   $fig->get_peg_keys()
                          );

	push(@tbl_attribute, ["Genome ID:", $cgi->textfield(-name => "att_data_genome_id",
						     -value => "",
                                                     -override => 1,
                                                     -size => 30)]);
	push(@tbl_attribute,["Select attribute", $cgi->popup_menu(-name => 'color_diagram_by_peg_tag', -values=>\@select_keys), $cgi->br]);
	my @values = ("all","essential","nonessential","potential_essential","undetermined");
        
	push(@tbl_attribute,["Select diagram", $cgi->popup_menu(-name => 'diagram_to_color', -values=>\@diagram_names), $cgi->br]);
	push(@tbl_attribute,["Select value", $cgi->popup_menu(-name => 'value_to_color', -values=>\@values), $cgi->br]);
	
	push(@$html, $cgi->h3("Color Diagram Roles by Essentiality Attribute Value"));
        push(@$html, $cgi->p("red=essential, blue=nonessential, gray=undetermined white=gene with matching value not present"));           
        push(@$html, &HTML::make_table(undef, \@tbl_attribute));
                
	push(@$html, $cgi->submit(-name => 'paint_diagram_role_by_attribute_value',
                                  -label => 'Color Matching Roles'));
  
    if ( $time_it )                  ## time ##
    {                                ## time ##
        push @times, scalar time();  ## time ##
        push @$html, "<br>dT = @{[$times[-1]-$times[-2]]}, T = @{[$times[-1]-$times[0]]}<br>";  ## time ##
    }                                ## time ##

    return @diagrams > 0;
}

sub tree_link {
    my $target = "window$$";
    my $url = &FIG::cgi_url . "/subsys.cgi?request=show_tree";
    return "<a href=$url target=$target>Show Phylogenetic Tree</a> (Shows the tree for all organisms in the SEED)";
}


#  There is a lot of blood, sweat and tears that go into computing the active
#  set of rows.  This is useful information to have later, when the user can
#  select genomes to be checked.  We will return the genome list as a reference
#  to a list of [ genomme_number => name ] pairs. -- GJO

sub format_rows {
    my($fig,$cgi,$html,$subsystem, $tagvalcolor, $have_diagrams) = @_;
    my($i,%alternatives);
    my $active_genome_list = [];

    my $ignore_alt = $cgi->param('ignore_alt');

    my $active_subsetC = ($cgi->param('active_subsetC') or $subsystem->get_active_subsetC );
    my $active_subsetR = ($cgi->param('active_subsetR') or $subsystem->get_active_subsetR );

    # RAE:
    # added this to allow determination of an active_subsetR based on a tag value pair
    if ($cgi->param('active_key')) 
    { 
        $active_subsetR = $cgi->param('active_key');
        my $active_value = undef;
        $active_value = $cgi->param('active_value') if ($cgi->param('active_value'));
        $subsystem->load_row_subsets_by_kv($active_subsetR, $active_value);
        $subsystem->set_active_subsetR($active_subsetR);
    }

    my @subsetC = $subsystem->get_subsetC_roles($active_subsetC);
    my %activeC = map { $_ => 1 } @subsetC;

    my @subsetR = $subsystem->get_subsetR($active_subsetR);
    my %activeR = map { $_ => 1 } @subsetR;

    if (! $ignore_alt)
    {
        my $subset;
        foreach $subset (grep { $_ =~ /^\*/ } sort $subsystem->get_subset_namesC)
        {
            my @mem = grep { $activeC{$_} } $subsystem->get_subsetC_roles($subset);
            if (@mem > 1)
            {
                my $mem = [@mem];
                foreach $_ (@mem)
                {
                    $alternatives{$_}->{$subset} = $mem;
                }
            }
        }
    }

    my @in = $subsystem->get_genomes;
    
    if (@in > 0)
    {
        my $col_hdrs = ["Genome ID","Organism"];
        
        if ($cgi->param('can_alter') && $user && ($user eq $subsystem->get_curator)) 
        {
            my $ssa  = $cgi->param('ssa_name');
            $ssa =~ s/[ \/]/_/g;
	    my $esc_ssa = uri_escape($ssa);
            push @$col_hdrs, "<a href=\"set_variants.cgi?user=$user&subsystem=$esc_ssa&request=show_variants\">Variant Code</a>";
        }
        else 
        {
            push @$col_hdrs, "Variant Code";
        }

        
        if ($cgi->param('color_by_ga')) {push @{$col_hdrs}, "Attribute"}

        my @row_guide = ();

        #  Add pop-up tool tip with role name to abbreviations in column header
        #  (a wonderful suggestion from Carl Woese). -- GJO

        my( $role, %in_col, %set_shown, $abbrev, $mem, $abbrev_html );
        foreach $role (grep { $activeC{$_} } $subsystem->get_roles)
        {
	    if ( $_ = $alternatives{ $role } )
	    {
		my @in = grep { ! $set_shown{$_} } sort keys(%$_);
		foreach $abbrev (@in)
		{
		    $set_shown{$abbrev} = 1;
		    $mem = $_->{$abbrev};

		    push( @row_guide, [ map { [ $_, "-" . ($subsystem->get_role_index($_) + 1) ] } @$mem ] );
		    foreach $_ ( @$mem ) { $in_col{ $_ } = 1 };  #  Mark the roles that are done
		    my $rolelist = join '<br>', map { substr($_->[1],1) . ". $_->[0]" } @{$row_guide[-1]};
		    $abbrev_html = "<a " . FIGjs::mouseover("Roles of $abbrev", $rolelist, '') . ">$abbrev</a>";
		    push( @$col_hdrs, $abbrev_html );
		}
	    }
	    elsif (! $in_col{$role})
	    {
		push( @row_guide, [ [ $role, "" ] ] );  #  No suffix on peg number
		$abbrev = $subsystem->get_role_abbr( $subsystem->get_role_index( $role ) );
		$abbrev_html = "<a " . FIGjs::mouseover("Role of $abbrev", $role, '') . ">$abbrev</a>";
		push( @$col_hdrs, $abbrev_html );
	    }
        }

        my $tab = [];
        my($genome,@pegs,@cells,$set,$peg_set,$pair,$role,$suffix,$row,$peg,$color_of,$cell,%count,$color,@colors);

        #
        #  Simplified code for checking variants -- GJO
        #  If specific variants are requested, make a hash of those to keep:
        #
        my $variant_list = undef;
        if ( $cgi->param( 'include_these_variants' ) )
        {
            $variant_list = { map { ($_, 1) } split( /\s*,\s*/, $cgi->param( 'include_these_variants' ) ) };
        }
        
        foreach $genome (grep { $activeR{$_} } @in)
        {
            my($genomeV,$vcodeV,$vcode_value);

            #  Get (and if necessary check) the variant code:

            $vcode_value = $subsystem->get_variant_code( $subsystem->get_genome_index( $genome ) );
            next if ( $variant_list && ( ! $variant_list->{ $vcode_value } ) );

            $row = [ $genome, &ext_genus_species($fig,$genome), $vcode_value ];
            push @$active_genome_list, [ $row->[0], $row->[1] ];   #  Save a list of the active genomes

            @pegs = ();
            @cells = ();

            foreach $set (@row_guide)
            {
                $peg_set = [];
                foreach $pair (@$set)
                {
                    ($role,$suffix) = @$pair;
                    foreach $peg ($subsystem->get_pegs_from_cell($genome,$role))
                    {
                        push(@$peg_set,[$peg,$suffix]);
                    }
                }
                push(@pegs,map { $_->[0] } @$peg_set);
                push(@cells,$peg_set);
            }
            $color_of = &group_by_clusters($fig,\@pegs);
            # RAE added a new call to get tag/value pairs
            # Note that $color_of is not overwritten.
            my $superscript;
            if ($cgi->param('color_by_ga')) 
            {
               # add colors based on the genome attributes
               # get the value
               my $ga=$cgi->param('color_by_ga');
               my $valuetype=$fig->guess_value_format($ga);
               my @array=$fig->get_attributes($genome, $ga);
               unless ($array[0]) {$array[0]=[]}
               # for the purposes of this page, we are going to color on the 
               # value of the last attribute
               my ($gotpeg, $gottag, $value, $url)=@{$array[0]};
               if (defined $value) # we don't want to color undefined values
               {
                  my @color=&cool_colors();
                  my $colval; # what we are basing the color on.
                  if ($valuetype->[0] eq "float") 
                  {
                    # Initially spllit numbers into groups of 10.
                    # $valuetype->[2] is the maximum number for this value
                    # but I don't like this
                    # $colval = int($value/$valuetype->[2]*10);
                    
                    # we want something like 0-1, 1-2, 2-3, 3-4 as the labels.
                    # so we will do it in groups of ten
                    my ($type, $min, $max)=@$valuetype;
                    for (my $i=$min; $i<$max; $i+=$max/10) {
                     if ($value >= $i && $value < $i+$max/10) {$colval = $i . "-" . ($i+($max/10))}
                    }
                  }
                  else {$colval=$value}
                  
                  if (!$tagvalcolor->{$colval}) {
                    # figure out the highest number used in the array
                    $tagvalcolor->{$colval}=0;
                    foreach my $t (keys %$tagvalcolor) {
                      ($tagvalcolor->{$t} > $tagvalcolor->{$colval}) ? $tagvalcolor->{$colval}=$tagvalcolor->{$t} : 1;
                    }
                    $tagvalcolor->{$colval}++;
                  }
                  # RAE Add a column for the description
                  splice @$row, 3, 0, $colval;

                  foreach my $cell (@cells) {
                    foreach $_ (@$cell)
                      {
                        $color_of->{$_->[0]} = $color[$tagvalcolor->{$colval}]
                      }
                  }
               }
               else 
               {
                # RAE Add a column for the description
                splice @$row, 3, 0, " &nbsp; ";
               }
            }
            if ($cgi->param("color_by_peg_tag")) 
            {
             ($color_of, $superscript, $tagvalcolor) = color_by_tag($fig, \@pegs, $color_of, $tagvalcolor, $cgi->param("color_by_peg_tag"));
            }
            foreach $cell ( @cells )  #  $cell = [peg, suffix]
            {
                #  Deal with the trivial case (no pegs) at the start
                
                if ( ! @$cell )
                {
                    #  Push an empty cell onto the row

                    push @$row, [" &nbsp; ", "td bgcolor='#FFFFFF'"];
                    next;
                }

                #  Figure out html text for each peg and cluster by color.

                my ( $peg, $suffix, $txt, $color );
                my @colors = ();
                my %text_by_color;   #  Gather like-colored peg text
                foreach ( @$cell )
                {
                    ( $peg, $suffix ) = @$_;
                    #  Hyperlink each peg, and add its suffix:
                    $txt = ( $cgi->param('ext_ids') ? external_id($fig,$cgi,$peg)
                                                    : HTML::fid_link($cgi,$peg, "local") )
                         . ( $suffix ? $suffix : '' );
                    $color = $color_of->{ $peg };
                    defined( $text_by_color{ $color } ) or push @colors, $color;
                    push @{ $text_by_color{ $color } }, $txt;
                }
                my $ncolors = @colors;

                #  Join text strings within a color (and remove last comma):

                my @str_by_color = map { [ $_, join( ', ', @{ $text_by_color{$_} }, '' ) ] } @colors;
                $str_by_color[-1]->[1] =~ s/, $//;

                #  Build the "superscript" string:

                my $sscript = "";
                if ( $superscript && @$cell )
                {
                    my ( %sscript, $ss );
                    foreach my $cv ( @$cell )  #  Should this be flattened across all pegs?
                    {
                        next unless ( $ss = $superscript->{ $cv->[0] } );
                        # my %flatten = map { ( $_, 1 ) } @$ss;
                        # $sscript{ join ",", sort { $a <=> $b } keys %flatten } = 1;  #  string of all values for peg
                        foreach ( @$ss ) { $sscript{ $_ } = 1 }
                    }
                    if (scalar keys %sscript)  # order by number, and format
                    {
                        my @ss = map  { $_->[0] }
                                 sort { $a->[1] <=> $b->[1] } 
                                 map  { my ( $num ) = $_ =~ /\>(\d+)\</; [ $_, $num || 0 ] } keys %sscript;
                        $sscript = "&nbsp;<sup>[" . join( ", ", @ss ) . "]</sup>"
                    }
                }

                my $cell_data;

                #  If there is one color, just write a unicolor cell.

                if ( $ncolors == 1 )
                {
                    my ( $color, $txt ) = @{ shift @str_by_color };
                    #$cell_data = qq(\@bgcolor="$color":) . $txt . $sscript;
                    # using this format allows other things (like excel writing to easily parse out data and formatting)
                    # the cell is a reference to an array. The first element is the data, and the second the formatting options
                    $cell_data = [$txt . $sscript, "td bgcolor=\"$color\""];
                }

                #  Otherwise, write pegs into a subtable with one cell per color.
                # RAE: used style for this rather than a separate table per cell. All the small tables are crap
                # for rendering, especially if you have a lot of pegs in a ss

                elsif(0)
                {
                    # original way
                    $cell_data = '<table><tr valign=bottom>'
                               . join( '', map { ( $color, $txt ) = @$_ ; qq(<td bgcolor="$color">$txt</td>) } @str_by_color )
                               . ( $sscript ? "<td>$sscript</td>" : '' )
                               . '</tr></table>';
                }

                else 
                {
                    $cell_data = join( '', map { ( $color, $txt ) = @$_ ; qq(<span style="background-color: $color">$txt</span>) } @str_by_color )
                                . ( $sscript ? $sscript : '' );
                }
                    
                

                #  Push the cell data onto the row:

                push(@$row, $cell_data);
            }
            push(@$tab,$row);
        }


        my $sort = $cgi->param('sort') || 'by_phylo';
        if ($sort eq "by_pattern")
        {
            my @tmp = ();
            my $row;
            foreach $row (@$tab)
            {
                my @var = ();
                my $i;
                for ($i=3; ($i < @$row); $i++)
                {
                    if (ref($row->[$i]) eq "ARRAY")
                    {
                        push(@var, ($row->[$i]->[0] =~ /\|/) ? 1 : 0);
                    }
                    else
                    {
                        push(@var, ($row->[$i] =~ /\|/) ? 1 : 0);
                    }
                }
                push(@tmp,[join("",@var),$row]);
            }
            $tab = [map { $_->[1] } sort { $a->[0] cmp $b->[0] } @tmp];
        }
        elsif ($sort eq "by_phylo")
        {
            $tab = [map      { $_->[0] }
                    sort     { ($a->[1] cmp $b->[1]) or ($a->[0]->[1] cmp $b->[0]->[1]) }
                    map      { [$_, $fig->taxonomy_of($_->[0])] }
                    @$tab];
        }
        elsif ($sort eq "by_tax_id")
        {
            $tab = [sort     { $a->[0] <=> $b->[0] } @$tab];
        }
        elsif ($sort eq "alphabetic")
        {
            $tab = [sort     { ($a->[1] cmp $b->[1]) or ($a->[0] <=> $b->[0]) } @$tab];
        }
        elsif ($sort eq "by_variant")
        {
            $tab = [sort     { ($a->[2] cmp $b->[2]) or ($a->[1] cmp $b->[1]) } @$tab];
        }
        
        foreach $row (@$tab)
        {
            next if ($row->[2] == -1 && !$cgi->param('show_minus1')); # RAE don't show -1 variants if checked
            my($genomeV,$vcodeV,$vcode_value);
            $genome = $row->[0];
            $vcode_value = $row->[2];
            if ($cgi->param('can_alter'))
            {
                $genomeV = $cgi->textfield(-name => "genome$genome", -size => 15, -value => $genome, -override => 1);
                $vcodeV  = $cgi->textfield(-name => "vcode$genome", -value => $vcode_value, -size => 10);
            }
            else
            {
                push(@$html,$cgi->hidden(-name => "genome$genome", -value => $genome, -override => 1),
                            $cgi->hidden(-name => "vcode$genome", -value => $vcode_value), "\n");
                $genomeV = $genome;
                $vcodeV  = $vcode_value;
            }

            $row->[0] = $genomeV;
            $row->[2] = $vcodeV;

            #
            # JS link for coloring diagrams.
            #

            if ($have_diagrams)
            {
                #my @roles = ("aspA");
		#my $colorJS = qq(<a href="" onclick="colorAttributeValue(@roles); return false;">Color</a>);
                my $colorJS = qq(<a href="" onclick="colorGenome('$genome'); return false;">Color</a>);
                $row->[0] .= " " . $colorJS;
            }
        }

        my $tab1 = [];
        
        foreach $row (@$tab)
        {
            next if ($row->[2] == -1 && !$cgi->param('show_minus1')); # RAE don't show -1 variants if checked
            if ((@$tab1 > 0) && ((@$tab1 % 10) == 0))
            {
                #push(@$tab1,[map { "<b>$_</b>" } @$col_hdrs]) ;
                # set this up using the table format feature so that we know it is a header
                push(@$tab1,[map { [$_, "th"] } @$col_hdrs]) ;
            }
            push(@$tab1,$row);
        }

        my %options; if ($cgi->param("create_excel")) {%options=(excelfile=>$cgi->param('ssa_name'), no_excel_link=>1)}
        $options{"class"}="white";
        push(@$html,$cgi->div({class=>"spreadsheet"}, &HTML::make_table($col_hdrs,$tab1,"Basic Spreadsheet", %options), $cgi->br),
                    $cgi->hr
             );


        my %sortmenu = (
            unsorted   => "None",
            alphabetic => "Alphabetical",
            by_pattern => "Patterns",
            by_phylo   => "Phylogeny",
            by_tax_id  => "Taxonomy",
            by_variant => "Variant Code",
        );

        push @$html, "Sort spreadsheet genomes by ",
                     $cgi->popup_menu( -name     => 'sort', 
                                       -values   => [sort keys %sortmenu],
                                       -labels   => \%sortmenu,
                                       -default  => $sort,
                                       -override => 1
                                     );
      
        push(@$html,'<br><br>Enter comma-separated list of variants to display in spreadsheet<br>', 
                $cgi->textfield(-name => "include_these_variants", -size => 50)
          );
      }

    if ( $time_it )                  ## time ##
    {                                ## time ##
        push @times, scalar time();  ## time ##
        push @$html, "<br>dT = @{[$times[-1]-$times[-2]]}, T = @{[$times[-1]-$times[0]]}<br>";  ## time ##
    }                                ## time ##

    # add an explanation for the colors if we want one.
    if ($cgi->param('color_by_ga'))
    {
     push(@$html, &HTML::make_table(undef,&describe_colors($tagvalcolor),"Color Descriptions<br><small>Link limits display to those organisms</small>"));
    }

    return $active_genome_list;  # [ [ id1, gs1 ], [ id2, gs2 ], ... ]
}


sub group_by_clusters {
    my($fig,$pegs) = @_;
    my($peg,@clusters,@cluster,@colors,$color,%seen,%conn,$x,$peg1,@pegs,$i);

    my $color_of = {};
    foreach $peg (@$pegs) { $color_of->{$peg} = '#FFFFFF' }

    if ($cgi->param('show_clusters'))
    {
        @pegs = keys(%$color_of);  #  Use of keys makes @pegs entries unique
        @clusters = $fig->compute_clusters(\@pegs,undef,5000);
        @colors =  &cool_colors();

        if (@clusters > @colors) { splice(@clusters,0,(@clusters - @colors)) }  # make sure we have enough colors

        my($cluster);
        foreach $cluster (@clusters)
        {
	    # RAE only color pegs if we have > 1 functional role involved in the cluster
	    my %countfunctions=map{(scalar $fig->function_of($_)=>1)} @$cluster;
	    next unless (scalar(keys %countfunctions) > 1);
	    
            $color = shift @colors;
            foreach $peg (@$cluster)
            {
                $color_of->{$peg} = $color;
            }
        }
    }
    return $color_of;
}


=head1 color_by_tag

 Change the color of cells by the pir superfamily. This is taken from the key/value pair
 Note that we will not change the color if $cgi->param('show_clusters') is set.

 This is gneric and takes the following arguments:
 fig, 
 pointer to list of pegs,
 pointer to hash of colors by peg,
 pointer to a hash that retains numbers across rows. The number is based on the value.
 tag to use in encoding

 eg. ($color_of, $superscript, $tagvalcolor) = color_by_tag($fig, $pegs, $color_of, $tagvalcolor, "PIRSF");
 
=cut

sub color_by_tag {
 # RAE added this so we can color individual cells across a column
 my ($fig, $pegs, $color_of, $tagvalcolor, $want)=@_;
 # figure out the colors and the superscripts for the pirsf
 # superscript will be a number
 # color will be related to the number somehow
 # url will be the url for each number
 my $number; my $url;
 my $count=0;
 #count has to be the highest number if we increment it
 foreach my $t (keys %$tagvalcolor) {($tagvalcolor->{$t} > $count) ? $count=$tagvalcolor->{$t} : 1}
 $count++; # this should now be the next number to assign
 foreach my $peg (@$pegs) {
  next unless (my @attr=$fig->get_attributes($peg));
  foreach my $attr (@attr) {
   next unless (defined $attr);
   my ($gotpeg, $tag, $val, $link)=@$attr;
   next unless ($tag eq $want);
   if ($tagvalcolor->{$val}) {
    $number->{$peg}=$tagvalcolor->{$val};
    push (@{$url->{$peg}}, "<a " . FIGjs::mouseover($tag, $val) . " href='$link'>" . $number->{$peg} . "</a>");
   }
   else {
    $number->{$peg}=$tagvalcolor->{$val}=$count++;
    push (@{$url->{$peg}}, "<a " . FIGjs::mouseover($tag, $val) . "href='$link'>" . $number->{$peg} . "</a>");
   }
    #### This is a botch at the moment. I want PIRSF to go to my page that I am working on, not PIR
    #### so I am just correcting those. This is not good, and I should change the urls in the tag/value pairs or something
    if ($want eq "PIRSF") {
     pop @{$url->{$peg}};
     $val =~ /(^PIRSF\d+)/;
     push (@{$url->{$peg}}, $cgi->a({href => "pir.cgi?&user=$user&pirsf=$1"}, $number->{$peg}));
    }
  }
 }


 # if we want to assign some colors, lets do so now
 my @colors = &cool_colors(); 
 unless ($cgi->param('show_clusters')) {
  foreach my $peg (@$pegs) { $color_of->{$peg} = '#FFFFFF' }
  foreach my $peg (keys %$number) {
   # the color is going to be the location in @colors
   unless ($number->{$peg} > @colors) {$color_of->{$peg}=$colors[$number->{$peg}-1]}
  }
 }
 return ($color_of, $url, $tagvalcolor);
}


sub format_ssa_table {
    my($cgi,$html,$user,$ssaP) = @_;
    my($ssa,$curator);
    my($url1,$link1);

    my $can_alter = $cgi->param('can_alter');
    push(@$html, $cgi->start_form(-action => "subsys.cgi",
                                  -method => 'post'),
                 $cgi->hidden(-name => 'user', -value => $user, -override => 1),
                 $cgi->hidden(-name => 'can_alter', -value => $can_alter, -override => 1),
                 $cgi->hidden(-name => 'request', -value => 'delete_or_export_ssa', -override => 1)
         );
    push(@$html,"<font size=\"+2\">Please do not ever edit someone else\'s spreadsheet (by using their
                 user ID), and <b>never open multiple windows to
                 process the same spreadsheet</b></font>.  It is, of course, standard practice to open a subsystem 
                 spreadsheet and then to have multiple other SEED windows to access data and modify annotations.  Further,
                 you can access someone else's subsystem spreadsheet using your ID (which will make it impossible
                 for you to edit the spreadsheet).
                 Just do not open the same subsystem spreadsheet for editing in multiple windows simultaneously.
                 A gray color means that the subsystem has no genomes attached to it. Go ahead and make these your own\n",
                 "<a href=\"Html/conflict_resolution.html\" class=\"help\" target=\"help\">Help on conflict resolution</a>\n",
         $cgi->br,
         $cgi->br
        );

# RAE: removed this from above push because VV want's it kept secret
#                "<a href=\"/FIG/Html/seedtips.html#change_ownership\" class=\"help\" target=\"help\">Help on changing subsystem ownership</a>\n",

# RAE: Added a new cgi param colsort for sort by column. This url will just recall the script with username to allow column sorting.
# RAE: Added a column to allow indexing of one subsystem. This is also going to be used in the renaming of a subsystem, too

    my $col_hdrs = [
                    "<a href='" . &FIG::cgi_url . "/subsys.cgi?user=$user&request=manage_ss'>Name</a><br><small>Sort by Subsystem</small>",
                    "<a href='" . &FIG::cgi_url . "/subsys.cgi?user=$user&colsort=curator&request=manage_ss'>Curator</a><br><small>Sort by curator</small>",
                    "NMPDR<br>Subsystem", "Distributable<br>Subsystem", "OK to Automatically<br>Extend", "Exchangable","Version",
                    "Reset to Previous Timestamp","Delete",
                    "Export Full Subsystem","Export Just Assignments", "Publish to Clearinghouse", "Reindex Subsystem",
                    ];
    my $title    = "Existing Subsystem Annotations";
    my $tab = [];
    my $userss; # this is a reference to a hash of all the subsystems the user can edit.
    foreach $_ (@$ssaP)
    {
        my($publish_checkbox, $index_checkbox);
        ($ssa,$curator) = @$_;

        my $esc_ssa = uri_escape($ssa);
        if ($curator eq $user) {push @$userss, $ssa}

        my($url,$link);
        if ((-d "$FIG_Config::data/Subsystems/$ssa/Backup") && ($curator eq $user))
        {
            $url = &FIG::cgi_url . "/subsys.cgi?user=$user&ssa_name=$esc_ssa&request=reset";
            $link = "<a href=$url>reset</a>";
        }
        else
        {
            $link = "";
        }

        # do we want to allow this in the NMPDR
        my $nmpdr;
        if ($curator eq $user)
        {
            $nmpdr=$cgi->checkbox(-name=> "nmpdr_ss", -value=>$ssa, -label=>"", -checked=>$fig->nmpdr_subsystem($ssa));
        }
        # do we want to allow this to be shared
        my $dist;
        if ($curator eq $user)
        {
            $dist=$cgi->checkbox(-name=> "dist_ss", -value=>$ssa, -label=>"", -checked=>$fig->distributable_subsystem($ssa));
        }

	# do we want to allow this to be automatically updated
	my $auto_update;
	if ($curator eq $user)
	{
		$auto_update=$cgi->checkbox(-name=> "auto_update_ok", -value=>$ssa, -label=>"", -checked=>$fig->ok_to_auto_update_subsys($ssa));
	}

        if (($fig->is_exchangable_subsystem($ssa)) && ($curator eq $user))
        {
            $url1  = &FIG::cgi_url . "/subsys.cgi?user=$user&ssa_name=$esc_ssa&request=make_unexchangable";
            $link1 = "Exchangable<br><a href=$url1>Make not exchangable</a>";
        }
        elsif ($curator eq $user)
        {
            $url1  = &FIG::cgi_url . "/subsys.cgi?user=$user&ssa_name=$esc_ssa&request=make_exchangable";
            $link1 = "Not exchangable<br><a href=$url1>Make exchangable</a>";
        }
        else
        {
            $link1 = "";
        }

        #
        # Only allow publish for subsystems we are curating?
        #
        if ($curator eq $user)
        {
            $publish_checkbox = $cgi->checkbox(-name => "publish_to_clearinghouse",
                                               -value => $ssa,
                                               -label => "Publish");

        }

	# Allow the user to set the variants
	my $set_variant_link = " &nbsp; ";
	if ($curator eq $user)
	{
		$set_variant_link = $cgi->a({href => "set_variants.cgi?subsystem=$esc_ssa&user=$user&request=show_variants"}, "Set variants");
	}

        #
        # Initially I am going to allow indexing of any subsystem since you may want to index it to allow
        # better searhing on a local system
        $index_checkbox=$cgi->checkbox(-name => "index_subsystem", -value=> $ssa, -label => "Index");

        # RAE color the background if the subsystem is empty
        # this uses a modification to HTML.pm that I made earlier to accept refs to arrays as cell data
        my $cell1=&ssa_link($fig,$ssa,$user);
        #unless (scalar $fig->subsystem_to_roles($ssa)) {$cell1 = [$cell1, 'td bgcolor="Dark grey"']} ## THIS IS DOG SLOW, BUT WORKS
        #unless (scalar $fig->get_subsystem($ssa)->get_genomes()) {$cell1 = [$cell1, 'td bgcolor="#A9A9A9"']} ## WORKS PERFECTLY, but sort of slow
        unless (scalar @{$fig->subsystem_genomes($ssa, 1)}) {$cell1 = [$cell1, 'td bgcolor="silver"']}

        push(@$tab,[
                    $cell1,
                    $curator,
                    $nmpdr,
                    $dist,
		    $auto_update,
                    $link1,
		    $set_variant_link,
                    $fig->subsystem_version($ssa),
                    $link,
                    ($curator eq $user) ? $cgi->checkbox(-name => "delete", -value => $ssa) : "",
                    $cgi->checkbox(-name => "export", -value => $ssa, -label => "Export full"),
                    $cgi->checkbox(-name => "export_assignments", -value => $ssa, -label => "Export assignments"),
                    $publish_checkbox, $index_checkbox,
                    ]);
    }
    push(@$html,
         &HTML::make_table($col_hdrs,$tab,$title),
         $cgi->hidden(-name => "users_ss",
                        -value=> $userss),
         $cgi->hidden(-name => "manage"),
         $cgi->submit(-name => "save_clicks",
                      -label => "Process Choices"),
         $cgi->submit(-name => 'delete_export',
                      -label => 'Process marked deletions and exports'),
         $cgi->submit(-name => 'publish',
                      -label => "Publish marked subsystems"),
         $cgi->submit(-name => 'reindex',
                      -label => "Reindex selected subsystems"),
         $cgi->end_form
         );
}

# RAE: I think this should be placed as a method in
# Subsystems.pm and called subsystems I know about or something.
# Cowardly didn't do though :-)
sub existing_subsystem_annotations {
    my($fig) = @_;
    my($ssa,$name);
    my @ssa = ();
    if (opendir(SSA,"$FIG_Config::data/Subsystems"))
    {
        @ssa = map { $ssa = $_; $name = $ssa; $ssa =~ s/[ \/]/_/g; [$name,&subsystem_curator($ssa)] } grep { $_ !~ /^\./ } readdir(SSA);
        closedir(SSA);
    }
    # RAE Adding sort of current subsystems
    if ($cgi->param('colsort') && $cgi->param('colsort') eq "curator")
    {
     # sort by the ss curator
     return sort { (lc $a->[1]) cmp (lc $b->[1]) || (lc $a->[0]) cmp (lc $b->[0]) } @ssa;
    } 
    else 
    {
     return sort { (lc $a->[0]) cmp (lc $b->[0]) } @ssa;
    }
}

sub ssa_link {
    my($fig,$ssa,$user) = @_;
    my $name = $ssa; $name =~ s/_/ /g;
    my $target = "window$$.$ssa";

    my $check;
    my $can_alter = $check = &subsystem_curator($ssa) eq $user;
    my $sort=$cgi->param('sort');
    my $show_clusters=$cgi->param('show_clusters');
    my $minus=$cgi->param('show_minus1');
    
    my $esc_ssa = uri_escape($ssa);
    my $url = &FIG::cgi_url . "/subsys.cgi?user=$user&ssa_name=$esc_ssa&request=show_ssa&can_alter=$can_alter&check=$check&sort=$sort&show_clusters=$show_clusters&show_minus1=$minus";
    return "<a href=$url target=$target>$name</a>";
}

sub log_update {
    my($ssa,$user) = @_;

    $ssa =~ s/[ \/]/_/g;

    if (open(LOG,">>$FIG_Config::data/Subsystems/$ssa/curation.log"))
    {
        my $time = time;
        print LOG "$time\t$user\tupdated\n";
        close(LOG);
    }
    else
    {
        print STDERR "failed to open $FIG_Config::data/Subsystems/$ssa/curation.log\n";
    }
}

sub export {
    my($fig,$cgi,$ssa) = @_;
    my($line);

    my ($exportable,$notes) = $fig->exportable_subsystem($ssa);
    foreach $line (@$exportable,@$notes)
    {
        print $line;
    }
}
        
sub export_assignments {
    my($fig,$cgi,$ssa) = @_;
    my(@roles,$i,$entry,$id,$user);

    if ($user && open(SSA,"<$FIG_Config::data/Subsystems/$ssa/spreadsheet"))
    {
        $user =~ s/^master://;
        &FIG::verify_dir("$FIG_Config::data/Assignments/$user");
        my $who = &subsystem_curator($ssa);
        my $file = &FIG::epoch_to_readable(time) . ":$who:generated_from_subsystem_$ssa";
        
        if (open(OUT,">$FIG_Config::data/Assignments/$user/$file"))
        {
            while (defined($_ = <SSA>) && ($_ !~ /^\/\//)) 
            {
                chop;
                push(@roles,$_);
            }
            while (defined($_ = <SSA>) && ($_ !~ /^\/\//))      {}
            while (defined($_ = <SSA>))
            {
                chop;
                my @flds = split(/\t/,$_);
                my $genome = $flds[0];
                for ($i=2; ($i < @flds); $i++)
                {
                    my @entries = split(/,/,$flds[$i]);
                    foreach $id (@entries)
                    {
                        my $peg = "fig|$genome.peg.$id";
                        my $func = $fig->function_of($peg);
                        print OUT "$peg\t$func\n";
                    }
                }
            }
            close(OUT);
        }
        close(SSA);
    }
}

sub format_missing {
    my($fig,$cgi,$html,$subsystem) = @_;
    my($org,$abr,$role,$missing);

    my $active_subsetC = ($cgi->param('active_subsetC') or $subsystem->get_active_subsetC );
    my $active_subsetR = ($cgi->param('active_subsetR') or $subsystem->get_active_subsetR );

    my @subsetC = $subsystem->get_subsetC_roles($active_subsetC);
    my %activeC = map { $_ => 1 } @subsetC;

    my @subsetR = $subsystem->get_subsetR($active_subsetR);

    my @alt_sets = grep { ($_ =~ /^\*/) } sort $subsystem->get_subset_namesC;
    my($set,$col,%in);
    foreach $set (@alt_sets) 
    {
        my @mem = grep { $activeC{$_} } $subsystem->get_subsetC_roles($set);
        foreach $col (@mem)
        {
            $in{$col} = $set;
        }
    }
    push(@$html,$cgi->h1('To Check Missing Entries:'));

    foreach $org (@subsetR)
    {
        my @missing = &columns_missing_entries($cgi,$subsystem,$org,\@subsetC,\%in);

        $missing = [];
        foreach $role (@missing)
        {
            $abr = $subsystem->get_role_abbr($subsystem->get_role_index($role));
            my $roleE = $cgi->escape($role);
            
            my $link = "<a href=" . &FIG::cgi_url . "/pom.cgi?user=$user&request=find_in_org&role=$roleE&org=$org>$abr $role</a>";
            push(@$missing,$link);
        }

        if (@$missing > 0)
        {
            my $genus_species = &ext_genus_species($fig,$org);
            push(@$html,$cgi->h2("$org: $genus_species"));
            push(@$html,$cgi->ul($cgi->li($missing)));
        }
    }
}

sub columns_missing_entries {
    my($cgi,$subsystem,$org,$roles,$in) = @_;

    my $just_genome = $cgi->param('just_genome');
    if ($just_genome && ($just_genome =~ /(\d+\.\d+)/) && ($org != $1)) { return () }

    my $just_col = $cgi->param('just_col');
    my(@really_missing) = ();

    my($role,%missing_cols);
    foreach $role (@$roles)
    {
        next if ($just_col && ($role ne $just_col));
        if ($subsystem->get_pegs_from_cell($org,$role) == 0)
        {
            $missing_cols{$role} = 1;
        }
    }

    foreach $role (@$roles)
    {
        if ($missing_cols{$role})
        {
            my($set);
            if (($set = $in->{$role}) && (! $cgi->param('ignore_alt')))
            {
                my @set = $subsystem->get_subsetC_roles($set);

                my($k);
                for ($k=0; ($k < @set) && $missing_cols{$set[$k]}; $k++) {}
                if ($k == @set)
                {
                    push(@really_missing,$role);
                }
            }
            else
            {
                push(@really_missing,$role);
            }
        }
    }
    return @really_missing;
}

sub format_missing_including_matches 
{
    my($fig,$cgi,$html,$subsystem) = @_;
    my($org,$abr,$role,$missing);

    my $active_subsetC = ($cgi->param('active_subsetC') or $subsystem->get_active_subsetC );
    my $active_subsetR = ($cgi->param('active_subsetR') or $subsystem->get_active_subsetR );

    my @subsetC = $subsystem->get_subsetC_roles($active_subsetC);
    my %activeC = map { $_ => 1 } @subsetC;

    my @subsetR = $subsystem->get_subsetR($active_subsetR);

    my @alt_sets = grep { ($_ =~ /^\*/) } sort $subsystem->get_subset_namesC;
    my($set,$col,%in);
    foreach $set (@alt_sets) 
    {
        my @mem = grep { $activeC{$_} } $subsystem->get_subsetC_roles($set);
        foreach $col (@mem)
        {
            $in{$col} = $set;
        }
    }
    push(@$html,$cgi->h1('To Check Missing Entries:'));

    push(@$html, $cgi->start_form(-action=> "fid_checked.cgi"));

    my $can_alter = $cgi->param('can_alter');
    push(@$html,
         $cgi->hidden(-name => 'user', -value => $user, -override => 1),
         $cgi->hidden(-name => 'can_alter', -value => $can_alter, -override => 1));

    my $just_role = &which_role($subsystem,$cgi->param('just_role'));
#   print STDERR "There are ", scalar @subsetR, " organisms to check\n";
    foreach $org (@subsetR)
    {
        my @missing = &columns_missing_entries($cgi,$subsystem,$org,\@subsetC,\%in);
        $missing = [];
        foreach $role (@missing)
        {
#           next if (($_ = $cgi->param('just_role')) && ($_ != ($subsystem->get_role_index($role) + 1)));
            next if ($just_role && ($just_role ne $role));

            my @hits = $fig->find_role_in_org($role, $org, $user, $cgi->param("sims_cutoff"));
            push(@$missing,@hits);
        }
#       print STDERR "Found ", scalar @$missing, " for $org\n";
        if (@$missing > 0)
        {
            my $genus_species = &ext_genus_species($fig,$org);
            push(@$html,$cgi->h2("$org: $genus_species"));

            my $colhdr = ["Assign", "P-Sc", "PEG", "Len", "Current fn", "Matched peg", "Len", "Function"];
            my $tbl = [];
            
            for my $hit (@$missing)
            {
                my($psc, $my_peg, $my_len, $my_fn, $match_peg, $match_len, $match_fn) = @$hit;

                my $my_peg_link = &HTML::fid_link($cgi, $my_peg, 1);
                my $match_peg_link = &HTML::fid_link($cgi, $match_peg, 0);

                my $checkbox = $cgi->checkbox(-name => "checked",
                                              -value => "to=$my_peg,from=$match_peg",
                                              -label => "");

                push(@$tbl, [$checkbox,
                             $psc,
                             $my_peg_link, $my_len, $my_fn,
                             $match_peg_link, $match_len, $match_fn]);
            }

            push(@$html, &HTML::make_table($colhdr, $tbl, ""));
        }
    }
    push(@$html,
         $cgi->submit(-value => "Process assignments",
                              -name => "batch_assign"),
         $cgi->end_form);
}



sub columns_missing_entries {
    my($cgi,$subsystem,$org,$roles,$in) = @_;

    next if (($_ = $cgi->param('just_genome')) && ($org != $_));
    my $just_col = $cgi->param('just_col');
    my(@really_missing) = ();

    my($role,%missing_cols);
    foreach $role (@$roles)
    {
        next if ($just_col && ($role ne $just_col));
        if ($subsystem->get_pegs_from_cell($org,$role) == 0)
        {
            $missing_cols{$role} = 1;
        }
    }

    foreach $role (@$roles)
    {
        if ($missing_cols{$role})
        {
            my($set);
            if (($set = $in->{$role}) && (! $cgi->param('ignore_alt')))
            {
                my @set = $subsystem->get_subsetC_roles($set);

                my($k);
                for ($k=0; ($k < @set) && $missing_cols{$set[$k]}; $k++) {}
                if ($k == @set)
                {
                    push(@really_missing,$role);
                }
            }
            else
            {
                push(@really_missing,$role);
            }
        }
    }
    return @really_missing;
}

sub format_missing_including_matches_in_ss 
{
    my($fig,$cgi,$html,$subsystem) = @_;
    my($org,$abr,$role,$missing);

    my $active_subsetC = ($cgi->param('active_subsetC') or $subsystem->get_active_subsetC );
    my $active_subsetR = ($cgi->param('active_subsetR') or $subsystem->get_active_subsetR );

    my @subsetC = $subsystem->get_subsetC_roles($active_subsetC);
    my %activeC = map { $_ => 1 } @subsetC;

    my @subsetR = $subsystem->get_subsetR($active_subsetR);

    my @alt_sets = grep { ($_ =~ /^\*/) } sort $subsystem->get_subset_namesC;
    my($set,$col,%in);
    foreach $set (@alt_sets) 
    {
        my @mem = grep { $activeC{$_} } $subsystem->get_subsetC_roles($set);
        foreach $col (@mem)
        {
            $in{$col} = $set;
        }
    }
    push(@$html,$cgi->h1('To Check Missing Entries:'));

    push(@$html, $cgi->start_form(-action=> "fid_checked.cgi"));

    my $can_alter = $cgi->param('can_alter');
    push(@$html,
         $cgi->hidden(-name => 'user', -value => $user, -override => 1),
         $cgi->hidden(-name => 'can_alter', -value => $can_alter, -override => 1));

    my $just_role = &which_role($subsystem,$cgi->param('just_role'));
    
    foreach $org (@subsetR)
    {
        my @missing = &columns_missing_entries($cgi,$subsystem,$org,\@subsetC,\%in);
        $missing = [];
        foreach $role (@missing)
        {
#           next if (($_ = $cgi->param('just_role')) && ($_ != ($subsystem->get_role_index($role) + 1)));
            next if ($just_role && ($just_role ne $role));

            my $flag = 0;
            my $filler;
            my $rdbH = $fig->db_handle;
            my $q = "SELECT subsystem, role FROM subsystem_index WHERE role = ?";
            if (my $relational_db_response = $rdbH->SQL($q, 0, $role))
            {
                my $pair;
                foreach $pair (@$relational_db_response)
                {
                     my ($ss, $role) = @$pair;
                     #if($ss =="")
                     #{
                      # $filler = 1; 
                     #}

                     if ($ss !~/Unique/)
                     {
                        $flag = 1; 
                     }
                }
            } 
            
            if ($flag == 1)
            {    
                my @hits = $fig->find_role_in_org($role, $org, $user, $cgi->param("sims_cutoff"));
                push(@$missing,@hits);
            }
        }

        if (@$missing > 0)
        {
            my $genus_species = &ext_genus_species($fig,$org);
            push(@$html,$cgi->h2("$org: $genus_species"));

            my $colhdr = ["Assign","Sub(s)", "P-Sc", "PEG", "Len", "Current fn", "Matched peg", "Len", "Function"];
            my $tbl = [];
            
            for my $hit (@$missing)
            {
                my($psc, $my_peg, $my_len, $my_fn, $match_peg, $match_len, $match_fn) = @$hit; 
                my $my_peg_link = &HTML::fid_link($cgi, $my_peg, 1);
                my $match_peg_link = &HTML::fid_link($cgi, $match_peg, 0);

                my $checkbox = $cgi->checkbox(-name => "checked",
                                              -value => "to=$my_peg,from=$match_peg",
                                              -label => "");
                my $good = 0;
                my @list_of_ss = ();
                my $ss_table_entry = "none";
                
                my (@list_of_returned_ss,$ss_name,$ss_role);
                @list_of_returned_ss = $fig->subsystems_for_peg($match_peg); 
                if (@list_of_returned_ss > 0)
                { 
                   for my $ret_ss (@list_of_returned_ss)
                   {
                      ($ss_name,$ss_role)= @$ret_ss;
                      if ($ss_name !~/Unique/)
                       { 
                           $good = 1;
                       }
                   }
                } 
                
                if ($good)
                {
                 my (@list_of_returned_ss,$ss_name,$ss_role);
                 @list_of_returned_ss = $fig->subsystems_for_peg($my_peg); 
                 if (@list_of_returned_ss > 0)
                 { 
                   for my $ret_ss (@list_of_returned_ss)
                   {
                      ($ss_name,$ss_role)= @$ret_ss;
                      if ($ss_name !~/Unique/)
                       { 
                           push (@list_of_ss,$ss_name);
                           $ss_table_entry = join("<br>",@list_of_ss);
                           
                       }
                   }
                }
            
                push(@$tbl, [$checkbox,$ss_table_entry,
                $psc,
                $my_peg_link, $my_len, $my_fn,
                $match_peg_link, $match_len, $match_fn]);
              }
               
            
            }

            push(@$html, &HTML::make_table($colhdr, $tbl, ""));
        }
    }
    push(@$html,
         $cgi->submit(-value => "Process assignments",
                              -name => "batch_assign"),
         $cgi->end_form);
}


sub format_check_assignments {
    my($fig,$cgi,$html,$subsystem) = @_;
    my($org,$role);

    my $active_subsetC = ($cgi->param('active_subsetC') or $subsystem->get_active_subsetC );
    my $active_subsetR = ($cgi->param('active_subsetR') or $subsystem->get_active_subsetR );

    my @subsetC = $subsystem->get_subsetC_roles($active_subsetC);
    my %activeC = map { $_ => 1 } @subsetC;

    my @subsetR = $subsystem->get_subsetR($active_subsetR);

    push(@$html,$cgi->h1('Potentially Bad Assignments:'));

    foreach $org (@subsetR)
    {
        next if (($_ = $cgi->param('just_genome_assignments')) && ($_ != $org));
        my @bad = ();

        foreach $role (@subsetC)
        {
            next if (($_ = $cgi->param('just_role_assignments')) && ($_ != ($subsystem->get_role_index($role) + 1)));
            push(@bad,&checked_assignments($cgi,$subsystem,$org,$role));
        }

        if (@bad > 0)
        {
            my $genus_species = &ext_genus_species($fig,$org);
            push(@$html,$cgi->h2("$org: $genus_species"),
                        $cgi->ul($cgi->li(\@bad)));
            
        }
    }
    push(@$html,$cgi->hr);
}

sub checked_assignments {
    my($cgi,$subsystem,$genome,$role) = @_;
    my($peg,$line1,$line2,@out,$curr,$auto);

    my(@bad) = ();
    my @pegs = $subsystem->get_pegs_from_cell($genome,$role);
    if (@pegs > 0)
    {
        my $tmp = "/tmp/tmp.pegs.$$";
        open(TMP,">$tmp") || die "could not open $tmp";
        foreach $peg (@pegs)
        {
            print TMP "$peg\n";
        }
        close(TMP);
        my $strict = $cgi->param('strict_check') ? "strict" : "";
        @out = `$FIG_Config::bin/check_peg_assignments $strict < $tmp 2> /dev/null`;
        unlink($tmp);

        while (($_ = shift @out) && ($_ =~ /^(fig\|\d+\.\d+\.peg\.\d+)/))
        {
            $peg = $1;
            if (($line1 = shift @out) && ($line1 =~ /^current:\s+(\S.*\S)/) && ($curr = $1) &&
                ($line2 = shift @out) && ($line2 =~ /^auto:\s+(\S.*\S)/) && ($auto = $1))
            {
                if (! $fig->same_func($curr,$auto))
                {
                    my $link = &HTML::fid_link($cgi,$peg);
                    push(@bad,"$link<br>$line1<br>$line2<br><br>");
                }
            }
        }
    }
    return @bad;
}

sub format_dups {
    my($fig,$cgi,$html,$subsystem) = @_;

    my $active_subsetC = ($cgi->param('active_subsetC') or $subsystem->get_active_subsetC );
    my $active_subsetR = ($cgi->param('active_subsetR') or $subsystem->get_active_subsetR );

    my @subsetC = $subsystem->get_subsetC_roles($active_subsetC);
    my %activeC = map { $_ => 1 } @subsetC;

    my @subsetR = $subsystem->get_subsetR($active_subsetR);

    push(@$html,$cgi->h1('To Check Duplicates:'));

    my($org,$duplicates,$role,$genus_species);
    foreach $org (@subsetR)
    {
        $duplicates = [];
        foreach $role (@subsetC)
        {
            my(@pegs,$peg,$func);
            if ((@pegs = $subsystem->get_pegs_from_cell($org,$role)) > 1)
            {
                push(@$duplicates,"$role<br>" . $cgi->ul($cgi->li([map { $peg = $_; $func = $fig->function_of($peg,$user); &HTML::fid_link($cgi,$peg) . " $func" } @pegs])));
            }
        }

        if (@$duplicates > 0)
        {
            $genus_species = &ext_genus_species($fig,$org);
            push(@$html,$cgi->h2("$org: $genus_species"));
            push(@$html,$cgi->ul($cgi->li($duplicates)));
        }
    }
}

sub format_coupled {
    my($fig,$cgi,$html,$subsystem,$type) = @_;
    my($i,$j,@show,$user,$org,$link,$gs,$func,$peg,$peg1,$peg2,%in,%seen,%seen2);
    my(@cluster,$sc,$x,$id2,@in,$sim,@coupled);
    my($org,$role);

    my $active_subsetC = ($cgi->param('active_subsetC') or $subsystem->get_active_subsetC );
    my $active_subsetR = ($cgi->param('active_subsetR') or $subsystem->get_active_subsetR );

    my @subsetC = $subsystem->get_subsetC_roles($active_subsetC);
    my %activeC = map { $_ => 1 } @subsetC;

    my @subsetR = $subsystem->get_subsetR($active_subsetR);

    foreach $org (@subsetR)
    {
        foreach $role (@subsetC)
        {
            push(@in,$subsystem->get_pegs_from_cell($org,$role));
        }
    }

    my @cdata = $fig->coupling_and_evidence_batch(\@in, 5000, 1.0e-10, 0.2, 1);
    my %cdata;
    map { push(@{$cdata{$_->[0]}}, [$_->[1], $_->[2]]) } @cdata;

    %in = map { $_ => 1 } @in;
    @show = ();
    foreach $peg1 (@in)
    {
        if ($type eq "careful")
        {
	    @coupled = @{$cdata{$peg1}};
            # @coupled = $fig->coupling_and_evidence($peg1,5000,1.0e-10,0.2,1);
        }
        elsif ($type eq "careful2")
        {
            @coupled = $fig->coupling_and_evidence($peg1,5000,1.0e-10,0.2,1);
        }
        else
        {
            @coupled = $fig->fast_coupling($peg1,5000,1);
        }

        foreach $x (@coupled)
        {
            ($sc,$peg2) = @$x;
            if ((! $in{$peg2}) && ((! $seen{$peg2}) || ($seen{$peg2} < $sc)))
            {
                $seen{$peg2} = $sc;
#               print STDERR "$sc\t$peg1 -> $peg2\n";
            }
        }
    }

    my @sims = $fig->sims([keys %seen], 1000, 1.0e-10, 'fig');
#    my %sims;
#    map { push(@{$sims{$_->id1}}, $_) } @sims;

    my $ns = @sims;
    warn "Retrieved $ns sims\n";
    
    foreach $peg1 (sort { $seen{$b} <=> $seen{$a} } keys(%seen))
    {
        if (! $seen2{$peg1})
        {
            @cluster = ($peg1);
            $seen2{$peg1} = 1;
            for ($i=0; ($i < @cluster); $i++)
            {
#                foreach $sim (@{$sims{$cluster[$i]}})
		foreach $sim (grep { $_->id1 eq $cluster[$i]} @sims)
#                foreach $sim ($fig->sims($cluster[$i],1000,1.0e-10,"fig"))
                {
                    $id2 = $sim->id2;
                    if ($seen{$id2} && (! $seen2{$id2}))
                    {
                        push(@cluster,$id2);
                        $seen2{$id2} = 1;
                    }
                }
            }
            push(@show, [scalar @cluster,
                         $cgi->br .
                         $cgi->ul($cgi->li([map { $peg = $_; 
                                                  $sc = $seen{$peg};
                                                  $func = $fig->function_of($peg,$user); 
                                                  $gs = $fig->genus_species($fig->genome_of($peg));
                                                  $link = &HTML::fid_link($cgi,$peg);
                                                  "$sc: $link: $func \[$gs\]" } 
                                            sort { $seen{$b} <=> $seen{$a} }
                                            @cluster]))
                         ]);
        }
    }

    if (@show > 0)
    {
        @show = map { $_->[1] } sort { $b->[0] <=> $a->[0] } @show;
        push(@$html,$cgi->h1('Coupled, but not in Spreadsheet:'));
        push(@$html,$cgi->ul($cgi->li(\@show)));
    }
}

#  Former behavior would convert Environmental Sample to E (for Eukaryota).
#  -- GJO

sub ext_genus_species {
    my( $fig, $genome ) = @_;

    my ( $gs, $c ) = $fig->genus_species_domain( $genome );
    $c = ( $c =~ m/^Environ/i ) ? 'M' : substr($c, 0, 1);  # M for metagenomic
    return "$gs [$c]";
}


sub show_tree {

    my($id,$gs);   
    my($tree,$ids) = $fig->build_tree_of_complete;
    my $relabel = {};
    foreach $id (@$ids)
    {
        if ($gs = $fig->genus_species($id))
        {
            $relabel->{$id} = "$gs ($id)";
        }
    }
    $_ = &display_tree($tree,$relabel);
    print $cgi->pre($_),"\n";
}

sub export_align_input
{

}

sub annotate_column {
    # RAE: I added this function to allow you to reannotate a single column all at once
    # this is because I wanted to update some of my annotations after looking at UniProt
    # and couldn't see an easy way to do it.
    my($fig,$cgi,$html,$col,$subsystem) = @_;
    my $checked;
    my $roles = [$subsystem->get_roles];
    my $role = &which_role_for_column($col,$roles);
    my @checked = &seqs_to_align($cgi,$role,$subsystem);
    return undef unless (@checked);
    
    # the following is read from fid_checked.cgi
    push( @$html, "<table border=1>\n",
                   "<tr><td>Protein</td><td>Organism</td><td>Current Function</td><td>By Whom</td></tr>"
        );
    
    foreach my $peg ( @checked ) {
        my @funcs = $fig->function_of( $peg );
        if ( ! @funcs ) { @funcs = ( ["", ""] ) }
        my $nfunc = @funcs;
        my $org = $fig->org_of( $peg );
        push( @$html, "<tr>",
                      "<td rowspan=$nfunc>$peg</td>",
                      "<td rowspan=$nfunc>$org</td>"
            );
        my ($who, $what);
        push( @$html, join( "</tr>\n<tr>", map { ($who,$what) = @$_; "<td>$what</td><td>$who</td>" } @funcs ) );
        push( @$html, "</tr>\n" );
    }
    push( @$html, "</table>\n" );

    push( @$html, $cgi->start_form(-action => "fid_checked.cgi", -target=>"_blank"),
              $cgi->br, $cgi->br,
              "<table>\n",
              "<tr><td>New Function:</td>",
              "<td>", $cgi->textfield(-name => "function", -size => 60), "</td></tr>",
              "<tr><td colspan=2>", $cgi->hr, "</td></tr>",
              "<tr><td>New Annotation:</td>",
              "<td rowspan=2>", $cgi->textarea(-name => "annotation", -rows => 30, -cols => 60), "</td></tr>",
              "<tr><td valign=top width=20%><br>", $cgi->submit('add annotation'), 
              "<p><b>Please note:</b> At the moment you need to make sure that the annotation in the table at the ",
              "top of this page reflects the new annotation. This may not be updated automatically.</p>",
              "</td></tr>",
              "</table>",
              $cgi->hidden(-name => 'user', -value => $user),
              $cgi->hidden(-name => 'checked', -value => [@checked]),
              $cgi->end_form
     );
}



sub align_column {
    my($fig,$cgi,$html,$colN,$subsystem) = @_;
    my(@pegs,$peg,$pseq,$role);

    my $roles = [$subsystem->get_roles];
    my $name = $subsystem->get_name;
    &check_index("$FIG_Config::data/Subsystems/$name/Alignments",$roles);
    if (($role = &which_role_for_column($colN,$roles)) &&
        ((@pegs = &seqs_to_align($cgi,$role,$subsystem)) > 1))
    {
        my $tmpF = "/tmp/seqs.fasta.$$";
        open(TMP,">$tmpF") || die "could not open $tmpF";

        foreach $peg (@pegs)
        {
            if ($pseq = $fig->get_translation($peg))
            {
                $pseq =~ s/[uU]/x/g;
                print TMP ">$peg\n$pseq\n";
            }
        }
        close(TMP);

        my $name = $subsystem->get_name;
        my $dir = "$FIG_Config::data/Subsystems/$name/Alignments/$colN";

        if (-d $dir)
        {
            system "rm -rf \"$dir\"";
        }

        &FIG::run("$FIG_Config::bin/split_and_trim_sequences \"$dir/split_info\" < $tmpF");

        if (-s "$dir/split_info/set.sizes")
        {
            open(SZ,"<$dir/split_info/set.sizes") || die " could not open $dir/split_info/set.sizes";
            while (defined($_ = <SZ>))
            {
                if (($_ =~ /^(\d+)\t(\d+)/) && ($2 > 3))
                {
                    my $n = $1;
                    &FIG::run("$FIG_Config::bin/make_phob_from_seqs \"$dir/$n\" < \"$dir/split_info\"/$n");
                }
            }
            close(SZ);
            &update_index("$FIG_Config::data/Subsystems/$name/Alignments/index",$colN,$role);
        }
        else
        {
            system("rm -rf \"$dir\"");
        }
    }
}

sub align_subcolumn {
    my($fig,$cgi,$html,$colN,$subcolN,$subsystem) = @_;
    my($role,@pegs,$cutoff,$peg);

    my $name = $subsystem->get_name;
    my $dir = "$FIG_Config::data/Subsystems/$name/Alignments/$colN/$subcolN";
    my $roles = [$subsystem->get_roles];
    if (&check_index("$FIG_Config::data/Subsystems/$name/Alignments",$roles))
    {
        my @pegs = map { $_ =~ /^([^ \t\n,]+)/; $1 } `cut -f2 $dir/ids`;

        if ($cutoff = $cgi->param('include_homo'))
        {
            my $max = $cgi->param('max_homo');
            $max = $max ? $max : 100;
            push(@pegs,&get_homologs($fig,\@pegs,$cutoff,$max));
        }

        system "rm -rf \"$dir\"";
        open(MAKE,"| make_phob_from_ids \"$dir\"") || die "could not make PHOB";
        foreach $peg (@pegs)
        {
            print MAKE "$peg\n";
        }
        close(MAKE);
    }
}

sub which_role_for_column {
    my($col,$roles) = @_;
    my($i);

    if (($col =~ /^(\d+)/) && ($1 <= @$roles))
    {
        return $roles->[$1-1];
    }
    return undef;
}

sub seqs_to_align {
    my($cgi,$role,$subsystem) = @_;
    my($genome);

    my $show_minus1 = $cgi->param('show_minus1');

    my @seqs = ();
    foreach $genome ($subsystem->get_genomes)
    {
	my $vcode_value = $subsystem->get_variant_code( $subsystem->get_genome_index( $genome ) );
	if ($show_minus1 || ($vcode_value ne "-1"))
	{	    
	    push(@seqs,$subsystem->get_pegs_from_cell($genome,$role));
	}
    }
    return @seqs;
}

sub get_homologs {
    my($fig,$checked,$cutoff,$max) = @_;
    my($peg,$sim,$id2);

    my @homologs = ();
    my %got = map { $_ => 1 } @$checked;
    my %new;

    foreach $peg (@$checked)
    {
	my $ln1 = length($fig->get_translation($peg));
        foreach $sim ($fig->sims($peg,300,$cutoff,"fig"))
        {
            $id2 = $sim->id2;
            if ((! $got{$id2}) && ((! $new{$id2}) || ($new{$id2} > $sim->psc)))
            {
		my $ln2 = length($fig->get_translation($id2));
                my $matched = abs($sim->e1 - $sim->b1);
                if ((($matched / $ln1) > 0.7) && (($matched / $ln2) > 0.7))
                {
                    $new{$id2} = $sim->psc;
                }
		else
		{
		    $got{$id2} = 1;
		}
            }
        }
    }
    @homologs = sort { $new{$a} <=> $new{$b} } keys(%new);
    if (@homologs > $max) { $#homologs = $max-1 }

    return @homologs;
}

sub set_links {
    my($cgi,$out) = @_;
   
    my @with_links = ();
    foreach $_ (@$out)
    {
        if ($_ =~ /^(.*)(fig\|\d+\.\d+\.peg\.\d+)(.*)$/)
        {
            my($before,$peg,$after) = ($1,$2,$3);
            push(@with_links, $before . &HTML::fid_link($cgi,$peg) . $after . "\n");
        }
        else
        {
            push(@with_links,$_);
        }
    }
    return @with_links;
}

sub reset_ssa {
    my($fig,$cgi,$html) = @_;
    my($ssa,@spreadsheets,$col_hdrs,$tab,$t,$readable,$url,$link,@tmp);

    if (($ssa = $cgi->param('ssa_name')) && opendir(BACKUP,"$FIG_Config::data/Subsystems/$ssa/Backup"))
    {
        @spreadsheets = sort { $b <=> $a }
                        map { $_ =~ /^spreadsheet.(\d+)/; $1 }
                        grep { $_ =~ /^spreadsheet/ } 
                        readdir(BACKUP);
        closedir(BACKUP);
        $col_hdrs = ["When","Number Genomes"];
        $tab = [];
        foreach $t (@spreadsheets)
        {
            $readable = &FIG::epoch_to_readable($t);
            $url = &FIG::cgi_url . "/subsys.cgi?user=$user&ssa_name=" . uri_escape( $ssa ) . "&request=reset_to&ts=$t";
            $link = "<a href=$url>$readable</a>";
            open(TMP,"<$FIG_Config::data/Subsystems/$ssa/Backup/spreadsheet.$t")
                || die "could not open $FIG_Config::data/Subsystems/$ssa/Backup/spreadsheet.$t";
            $/ = "//\n";
            $_ = <TMP>;
            $_ = <TMP>;
            $_ = <TMP>;
            chomp;
            $/ = "\n";

            @tmp = grep { $_ =~ /^\d+\.\d+/ } split(/\n/,$_);
            push(@$tab,[$link,scalar @tmp]);
        }
    }
    push(@$html,&HTML::make_table($col_hdrs,$tab,"Possible Points to Reset From"));
}

sub reset_ssa_to {
    my($fig,$cgi,$html) = @_;
    my($ts,$ssa);

    if (($ssa = $cgi->param('ssa_name')) &&
         ($ts = $cgi->param('ts')) && 
         (-s "$FIG_Config::data/Subsystems/$ssa/Backup/spreadsheet.$ts"))
    {
        system "cp -f $FIG_Config::data/Subsystems/$ssa/Backup/spreadsheet.$ts $FIG_Config::data/Subsystems/$ssa/spreadsheet";
        chmod(0777,"$FIG_Config::data/Subsystems/$ssa/spreadsheet");

        if (-s "$FIG_Config::data/Subsystems/$ssa/Backup/notes.$ts")
        {
            system "cp -f $FIG_Config::data/Subsystems/$ssa/Backup/notes.$ts $FIG_Config::data/Subsystems/$ssa/notes";
            chmod(0777,"$FIG_Config::data/Subsystems/$ssa/notes");
        }

        if (-s "$FIG_Config::data/Subsystems/$ssa/Backup/reactions.$ts")
        {
            system "cp -f $FIG_Config::data/Subsystems/$ssa/Backup/reactions.$ts $FIG_Config::data/Subsystems/$ssa/reactions";
            chmod(0777,"$FIG_Config::data/Subsystems/$ssa/reactions");
        }

        if (-s "$FIG_Config::data/Subsystems/$ssa/Backup/hope_reactions.$ts")
        {
            system "cp -f $FIG_Config::data/Subsystems/$ssa/Backup/hope_reactions.$ts $FIG_Config::data/Subsystems/$ssa/hope_reactions";
            chmod(0777,"$FIG_Config::data/Subsystems/$ssa/hope_reactions");
        }

        if (-s "$FIG_Config::data/Subsystems/$ssa/Backup/hope_reaction_notes.$ts")
        {
            system "cp -f $FIG_Config::data/Subsystems/$ssa/Backup/hope_reaction_notes.$ts $FIG_Config::data/Subsystems/$ssa/hope_reaction_notes";
            chmod(0777,"$FIG_Config::data/Subsystems/$ssa/hope_reaction_notes");
        }

        if (-s "$FIG_Config::data/Subsystems/$ssa/Backup/hope_reaction_links.$ts")
        {
            system "cp -f $FIG_Config::data/Subsystems/$ssa/Backup/hope_reaction_links.$ts $FIG_Config::data/Subsystems/$ssa/hope_reaction_links";
            chmod(0777,"$FIG_Config::data/Subsystems/$ssa/hope_reaction_links");
        }
	
        if (-s "$FIG_Config::data/Subsystems/$ssa/Backup/hope_kegg_info.$ts")
        {
            system "cp -f $FIG_Config::data/Subsystems/$ssa/Backup/hope_kegg_info.$ts $FIG_Config::data/Subsystems/$ssa/hope_kegg_info";
            chmod(0777,"$FIG_Config::data/Subsystems/$ssa/hope_kegg_info");
        }

        my $subsystem = new Subsystem($ssa,$fig,0);
        $subsystem->db_sync(0);
        undef $subsystem;
    }
}
                
sub make_exchangable {
    my($fig,$cgi,$html) = @_;
    my($ssa);

    if (($ssa = $cgi->param('ssa_name')) &&
         (-s "$FIG_Config::data/Subsystems/$ssa/spreadsheet") &&
        open(TMP,">$FIG_Config::data/Subsystems/$ssa/EXCHANGABLE"))
    {
        print TMP "1\n";
        close(TMP);
        chmod(0777,"$FIG_Config::data/Subsystems/$ssa/EXCHANGABLE");
    }
}

sub make_unexchangable {
    my($fig,$cgi,$html) = @_;
    my($ssa);

    if (($ssa = $cgi->param('ssa_name')) &&
         (-s "$FIG_Config::data/Subsystems/$ssa/EXCHANGABLE"))
    {
        unlink("$FIG_Config::data/Subsystems/$ssa/EXCHANGABLE");
    }
}

sub which_role {
    my($subsystem,$role_indicator) = @_;
    my($n,$role,$abbr);

    if (($role_indicator =~ /^\s*(\d+)\s*$/) && ($n = $1) && ($role = $subsystem->get_role($n-1)))
    {
        return $role;
    }
    elsif (($role_indicator =~ /^\s*(\S+)\s*$/) && ($abbr = $1) && ($role = $subsystem->get_role_from_abbr($abbr)))
    {
        return $role;
    }
    return "";
}

sub external_id {
    my($fig,$cgi,$peg) = @_;
    my @tmp;
    my @aliases = $fig->feature_aliases($peg);
    if      ((@tmp = grep { $_ =~ /^uni\|/ } @aliases) > 0)
    {
        @aliases = map { &HTML::uni_link($cgi,$_) } @tmp;
    }
    elsif   ((@tmp = grep { $_ =~ /^sp\|/ } @aliases) > 0)
    {
        @aliases = map { &HTML::sp_link($cgi,$_) } @tmp;
    }
    elsif   ((@tmp = grep { $_ =~ /^gi\|/ } @aliases) > 0)
    {
        @aliases = map { &HTML::gi_link($cgi,$_) } @tmp;
    }
    elsif   ((@tmp = grep { $_ =~ /^kegg\|/ } @aliases) > 0)
    {
        @aliases = map { &HTML::kegg_link($cgi,$_) } @tmp;
    }
    else
    {
        return wantarray() ? (&HTML::fid_link($cgi,$peg)) : &HTML::fid_link($cgi,$peg);
    }

    if (wantarray())
    {
        return @aliases;
    }
    else
    {
        return $aliases[0];
    }
}

sub cool_colors {
 # just an array of "websafe" colors or whatever colors we want to use. Feel free to remove bad colors (hence the lines not being equal length!)
 return (
 '#C0C0C0', '#FF40C0', '#FF8040', '#FF0080', '#FFC040', '#40C0FF', '#40FFC0', '#C08080', '#C0FF00', '#00FF80', '#00C040',
 "#6B8E23", "#483D8B", "#2E8B57", "#008000", "#006400", "#800000", "#00FF00", "#7FFFD4",
 "#87CEEB", "#A9A9A9", "#90EE90", "#D2B48C", "#8DBC8F", "#D2691E", "#87CEFA", "#E9967A", "#FFE4C4", "#FFB6C1",
 "#E0FFFF", "#FFA07A", "#DB7093", "#9370DB", "#008B8B", "#FFDEAD", "#DA70D6", "#DCDCDC", "#FF00FF", "#6A5ACD",
 "#00FA9A", "#228B22", "#1E90FF", "#FA8072", "#CD853F", "#DC143C", "#FF6347", "#98FB98", "#4682B4",
 "#D3D3D3", "#7B68EE", "#2F4F4F", "#FF7F50", "#FF69B4", "#BC8F8F", "#A0522D", "#DEB887", "#00DED1",
 "#6495ED", "#800080", "#FFD700", "#F5DEB3", "#66CDAA", "#FF4500", "#4B0082", "#CD5C5C",
 "#EE82EE", "#7CFC00", "#FFFF00", "#191970", "#FFFFE0", "#DDA0DD", "#00BFFF", "#DAA520", "#008080",
 "#00FF7F", "#9400D3", "#BA55D3", "#D8BFD8", "#8B4513", "#3CB371", "#00008B", "#5F9EA0",
 "#4169E1", "#20B2AA", "#8A2BE2", "#ADFF2F", "#556B2F",
 "#F0FFFF", "#B0E0E6", "#FF1493", "#B8860B", "#FF0000", "#F08080", "#7FFF00", "#8B0000",
 "#40E0D0", "#0000CD", "#48D1CC", "#8B008B", "#696969", "#AFEEEE", "#FF8C00", "#EEE8AA", "#A52A2A",
 "#FFE4B5", "#B0C4DE", "#FAF0E6", "#9ACD32", "#B22222", "#FAFAD2", "#808080", "#0000FF",
 "#000080", "#32CD32", "#FFFACD", "#9932CC", "#FFA500", "#F0E68C", "#E6E6FA", "#F4A460", "#C71585",
 "#BDB76B", "#00FFFF", "#FFDAB9", "#ADD8E6", "#778899",
 );
}

sub describe_colors {
 my ($tvc)=@_;
 my $tab = [];
 my @colors=&cool_colors();
 my @labels=sort {$a cmp $b} keys %$tvc;
 my $selfurl=$cgi->url();
 # recreate the url for the link
 $selfurl .= "?user=" . $user
          .  "&ssa_name=" . uri_escape( $cgi->param('ssa_name') )
          .  "&request=" . $cgi->param('request')
          .  "&can_alter=" . $cgi->param('can_alter');
 
 my $row;
 for (my $i=0; $i<= scalar @labels; $i++) {
  next unless (defined $labels[$i]);
  my $link='<a href="' . $selfurl . "&active_key=" . $cgi->param('color_by_ga') . "&active_value=" . $labels[$i] . '">' . $labels[$i] . "</a>\n";
  push @$row, [$link, "td style=\"background-color: $colors[$tvc->{$labels[$i]}]\""];
  unless (($i+1) % 10) {
   push @$tab, $row;
   undef $row;
  }
 }
 push @$tab, $row;
 return $tab;
}

sub existing_trees {
    my($dir,$roles) = @_;
    my(@rolesI,$roleI,@subrolesI,$subroleI);

    &check_index("$dir/Alignments",$roles);

    my @rolesA = ();

    if (opendir(DIR,"$dir/Alignments"))
    {
        @rolesI = grep { $_ =~ /^(\d+)$/ } readdir(DIR);
        closedir(DIR);

        foreach $roleI (@rolesI)
        {
            if ((-d "$dir/Alignments/$roleI/split_info") && opendir(SUBDIR,"$dir/Alignments/$roleI"))
            {
                @subrolesI = grep { $_ =~ /^(\d+)$/ } readdir(SUBDIR);
                closedir(SUBDIR);

                foreach $subroleI (@subrolesI)
                {
                    push(@rolesA,"$roleI.$subroleI: $roles->[$roleI-1]");
                }
            }
        }
    }

    my($x,$y);
    return [sort { $a =~ /^(\d+\.\d+)/; $x = $1; 
                   $b =~ /^(\d+\.\d+)/; $y = $1;
                   $x <=> $y
                  } @rolesA];
}

sub check_index {
    my($alignments,$roles) = @_;

    if (-s "$alignments/index")
    {
        my $ok = 1;
        foreach $_ (`cat \"$alignments/index\"`)
        {
            $ok = $ok && (($_ =~ /^(\d+)\t(\S.*\S)/) && ($roles->[$1 - 1] eq $2));
        }
        if (! $ok)
        {
            system "rm -rf \"$alignments\"";
            return 0;
        }
        return 1;
    }
    else
    {
        system "rm -rf \"$alignments\"";
    }
    return 0;
}

sub update_index {
    my($file,$colN,$role) = @_;

    my @lines = ();
    if (-s $file)
    {
        @lines = grep { $_ !~ /^$colN\t/ } `cat $file`;
    }
    push(@lines,"$colN\t$role\n");
    open(TMP,">$file") || die "could not open $file";
    foreach $_ (@lines)
    {
        print TMP $_;
    }
    close(TMP);
}

sub show_sequences_in_column {
    my($fig,$cgi,$html,$subsystem,$colN) = @_;
    my(@pegs,$role);

    my $roles = [$subsystem->get_roles];
    if (($role = &which_role_for_column($colN,$roles)) &&
        ((@pegs = &seqs_to_align($cgi,$role,$subsystem)) > 0))
    {
        push(@$html, "<pre>\n");
        foreach my $peg (@pegs)
        {
            my $seq;
            if ($seq = $fig->get_translation($peg))
            {
		my $func = $fig->function_of($peg);
		my $org  = $fig->genus_species(&FIG::genome_of($peg));
                push(@$html,  ">$peg [$org] [$func]\n",&formatted_seq($seq),"\n");
            }
            else
            {
                push(@$html, "could not find translation for $peg\n");
            }
        }
        push(@$html, "\n</pre>\n");
    }
    else
    {
        push(@$html,$cgi->h1("Could not determine the role from $colN"));
    }
}
    
sub formatted_seq {
    my($seq) = @_;
    my($i,$ln);

    my @seqs = ();
    my $n = length($seq);
    for ($i=0; ($i < $n); $i += 60) {
        if (($i + 60) <= $n) {
            $ln = substr($seq,$i,60);
        } else {
            $ln = substr($seq,$i,($n-$i));
        }
        push(@seqs,"$ln\n");
    }
    return @seqs;
}

sub check_ssa {
    my($fig,$cgi) = @_;

    my $ssa  = $cgi->param('ssa_name');
    my $checked;
    if ($user && $ssa)
    {
        $ENV{'REQUEST_METHOD'} = 'GET';
        $ENV{'QUERY_STRING'} = "user=$user&subsystem=$ssa&request=check_ssa";
        $checked = join("",`$FIG_Config::fig/CGI/check_subsys.cgi`);
        if ($checked =~ /^.*?(<form .*form>)/s)
        {
            return $1;
        }
    }
    return "";
}


sub moregenomes {
    my $more=$cgi->param('moregenomes');
    $cgi->delete('moregenomes');
    if ($more eq "Cyanobacteria")              {return &selectgenomeattr("phylogeny", "Cyanobacteria")}
    if ($more eq "NMPDR")                      {return &selectgenomeattr("filepresent", "NMPDR")}
    if ($more eq "BRC")                        {return &selectgenomeattr("filepresent", "BRC")}
    if ($more eq "Higher Plants")              {return &selectgenomeattr("higher_plants")}
    if ($more eq "Photosynthetic Eukaryotes")  {return &selectgenomeattr("eukaryotic_ps")}
    if ($more eq "Anoxygenic Phototrophs")     {return &selectgenomeattr("nonoxygenic_ps")}
    if ($more eq "Hundred by a hundred")       {return &selectgenomeattr("hundred_hundred")}
    if ($more eq "Functional Coupling Paper")  {return &selectgenomeattr("functional_coupling_paper")}
    if ($more eq "Phages")		       {return &selectgenomeattr("virus_type", "Phage")}
}
        
sub selectgenomeattr {
    my ($tag, $value)=@_;
    my @orgs;
    if ($tag eq "phylogeny")
    {
        my $taxonomic_groups = $fig->taxonomic_groups_of_complete(10);
        foreach my $pair (@$taxonomic_groups)
        { 
            push @orgs, @{$pair->[1]} if ($pair->[0] eq "$value");
        }
    }
    elsif ($tag eq "filepresent")
    {
        foreach my $genome ($fig->genomes)
        {
            push(@orgs, $genome) if (-e $FIG_Config::organisms."/$genome/$value");
        }
    }
    else
    {
        if ($value) {@orgs=map {$_->[0]} grep {$_->[0] =~ /^\d+\.\d+$/} $fig->get_attributes(undef, $tag, $value)}
        else {@orgs=map {$_->[0]} grep {$_->[0] =~ /^\d+\.\d+$/} $fig->get_attributes(undef, $tag)}
    }
    @orgs = grep {$fig->is_genome($_)} @orgs;
    return @orgs;
}

sub subsystem_curator {
    my($ssa) = @_;

    my $curator = $fig->subsystem_curator($ssa);

    if (($curator =~ /^\S/) && ($curator !~ /^master:/)) { $curator = "master:$curator" }
    return $curator;
}
