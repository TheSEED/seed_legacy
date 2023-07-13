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
my $fig = new FIG;

use HTML;
use strict;

use CGI;
my $cgi = new CGI;

if (0)
{
    print $cgi->header;
    my @params = $cgi->param;
    print "<pre>\n";
    foreach $_ (@params)
    {
	print "$_\t:",join(",",$cgi->param($_)),":\n";
    }
    exit;
}

my $html = [];

my $user = $cgi->param('user');
if ($user !~ /^master:/) { "master:$user" }

if (! $user)
{
    push(@$html,$cgi->h1("Sorry, you need to specify a user to process assignment sets"));
}
else
{
    my $request = $cgi->param("request");
    $request = defined($request) ? $request : "";

    if ($cgi->param('delete checked entries'))
    {
	&delete_checked($fig,$cgi,$html);
	$cgi->delete('delete checked entries');
	$cgi->delete("request");
	$cgi->delete("set");
	&show_initial($fig,$cgi,$html);
    }
    elsif    ($request eq "edit_set")
    {
	&edit_set($fig,$cgi,$html);
    }
    elsif ($request eq "delete_set")
    {
	&delete_set($fig,$cgi,$html);
    }
    elsif ($request eq "accept_set")
    {
	&accept_set($fig,$cgi,$html);
    }
    else
    {
	&show_initial($fig,$cgi,$html);
    }
}

&HTML::show_page($cgi,$html);

sub show_initial {
    my($fig,$cgi,$html) = @_;
    my($set,$when,$comment);

    my $user = $cgi->param('user');
    my @sets = &assignment_sets($user);
    if (@sets == 0)
    {
	push(@$html,$cgi->h1("No Assignment Sets Defined"));
	return;
    }

    my $target = "window$$";
    push(@$html, $cgi->h1('Assignment Sets'),
                 $cgi->start_form(-action => "assignments.cgi",
				  -target => $target,
				  -method => 'post'),
	         $cgi->hidden(-name => 'user', -value => $user),
	 );

    my $col_hdrs = ["Edit/Examine","Delete","Accept All","Set Date","Comment"];
    my $tab      = [];
    my $title    = "Existing Assignment Sets";

    foreach $set (sort { &compare_set_names($a,$b) } @sets)
    {
	$set =~ /(\d+-\d+-\d+:\d+:\d+:\d+)(:(.*))?/;
	$when    = $1;
	$comment = $3;
	push(@$tab,[
		    &edit_link($cgi,$set),
		    &delete_link($cgi,$set),
		    &accept_link($cgi,$set),
		    $when,
		    $comment
		   ]
	     );
    }
    push(@$html,&HTML::make_table($col_hdrs,$tab,$title));
}		  

sub edit_link {
    my($cgi,$set) = @_;
    
    # modified by RAE so that this can be called from within assignments.cgi and the options can be changed.
    return "<a href=" . $cgi->url(-relative => 1) . "?user=".$cgi->param('user') . "&request=edit_set&set=$set&all=0>edit</a>" . "/" .
	   "<a href=" . $cgi->url(-relative => 1) . "?user=".$cgi->param('user') . "&request=edit_set&set=$set&all=1>examine</a>";
}

sub delete_link {
    my($cgi,$set) = @_;

    # modified by RAE so that this can be called from within assignments.cgi and the options can be changed.
    return "<a href=" . $cgi->url(-relative => 1) . "?user=".$cgi->param('user')."&request=delete_set&set=$set>delete</a>";
    #return "<a href=" . $cgi->self_url() . "&request=delete_set&set=$set>delete</a>";
}

sub accept_link {
    my($cgi,$set) = @_;

    # modified by RAE so that this can be called from within assignments.cgi and the options can be changed.
    return "<a href=" . $cgi->url(-relative => 1) . "?user=".$cgi->param('user')."&request=accept_set&set=$set>accept</a>";
}

sub assignment_sets {
    my($user) = @_;

    my $userR = $user;
    $userR =~ s/^master://;
    my @sets = ();
    if (opendir(SETS,"$FIG_Config::data/Assignments/$userR"))
    {
	@sets = grep { $_ =~ /^\d+-\d+-\d+:\d+:\d+:\d+/ } readdir(SETS);
	closedir(SETS);
    }
    return @sets;
}
	
sub compare_set_names {
    my($a,$b) = @_;
    my(@whenA,@whenB,$i);

    if (($a =~ /^(\d+)-(\d+)-(\d+):(\d+):(\d+):(\d+)(.*)/) && (@whenA = ($3,$1,$2,$4,$5,$6,$7)) &&
	($b =~ /^(\d+)-(\d+)-(\d+):(\d+):(\d+):(\d+)(.*)/) && (@whenB = ($3,$1,$2,$4,$5,$6,$7)))
    {
	for ($i=0; ($i < 6) && ($whenA[$i] == $whenB[$i]); $i++) {}
	if ($i < 6)
	{
	    return ($whenA[$i] <=> $whenB[$i]);
	}
	else
	{
	    return ($whenA[6] cmp $whenB[6]);
	}
    }
    return ($a cmp $b);
}

sub edit_set {
    my($fig,$cgi,$html) = @_;
    my($line,$userR,$func1,$func2,$col_hdrs,$tab,$peg,$conf);

    my $user = $cgi->param('user');
    if (! $user)
    {
	push(@$html,$cgi->h1("Sorry, but you need to specify a user to edit assignments"));
	return;
    }
    else
    {
	$userR = $user;
	$userR =~ s/^master://;
    }

    my $set  = $cgi->param('set');
    if (! $set)
    {
	push(@$html,$cgi->h1("Sorry, but you need to specify a set to edit"));
	return;
    }

    my $target = "window$$";
    if (-e "$FIG_Config::data/Assignments/$userR/$set")
    {
	if (open(SET,"<$FIG_Config::data/Assignments/$userR/$set"))
	{
	    my $op = $cgi->param('all') ? "Examine" : "Edit";
	    push(@$html, $cgi->h1("$op Set $set"),
		         $cgi->start_form(-method => 'post',
					  -target => $target,
					  -action => 'assignments.cgi'
					  ),
		         $cgi->hidden(-name => 'user', -value => $user),
		         $cgi->hidden(-name => 'set', -value => $set)
		 );

	    $col_hdrs = ["delete","PEG","In SubSys","Proposed Function", "Current function","UniProt ID","UniProt Function"];
	    $tab      = [];
	    my @keep = ();
	    while (defined($line = <SET>))
	    {
		chop $line;
		($peg,$func1,$conf) = split(/\t/,$line);
		if ($conf) { $func1 = "$func1\t$conf" }
		$func2 = &func_of($fig,$peg,$user);
		if ($func1 ne $func2)
		{
		    push(@keep,"$line\n");
		    my @subs    = $fig->peg_to_subsystems($peg);
		    my $in_sub  = @subs;
		    my @uni = $fig->to_alias($peg,"uni");
		    my $uni_link = (@uni > 0) ? &HTML::uni_link($cgi,$uni[0]) : "";
		    my $uni_func = $uni_link ? $fig->function_of($uni[0]) : "";
		    push(@$tab,[
			        $cgi->checkbox(
                                               -name => 'checked', 
	                                       -value => $peg, 
	                                       -checked => 0,
	                                       -override => 1, 
	                                       -label => ""
	                                      ),
				&HTML::fid_link($cgi,$peg),
				$in_sub,
				$func1, $func2,
				$uni_link,$uni_func
			       ]
			 );
		}
	    }
	    close(SET);

	    if (@$tab > 0)
	    {
		push(@$html,&HTML::make_table($col_hdrs,$tab,""));
		push(@$html,$cgi->submit("delete checked entries"));
		# modified by RAE to include these links at the bottom of the page so that you can accept after reviewing
		push(@$html,"<p><b>", &accept_link($cgi, $set), "/", &edit_link($cgi, $set), " these annotations</b></p>");
	    }
	    else
	    {
		push(@$html,$cgi->h2("No new assignments"));
	    }
	}
	else
	{
	    push(@$html,$cgi->h1("Sorry, could not open $FIG_Config::data/Assignments/$userR/$set; sounds like a permissions problem"));
	}
    }
    else
    {
	push(@$html,$cgi->h1("Sorry, $set does not exist for user $user"));
    }
}

sub delete_set {
    my($fig,$cgi,$html) = @_;

    my $user = $cgi->param('user');
    my $userR = $user;
    $userR =~ s/^master://;
    my $set  = $cgi->param('set');
    if (-e "$FIG_Config::data/Assignments/$userR/$set")
    {
	unlink("$FIG_Config::data/Assignments/$userR/$set");
	push(@$html,$cgi->h2("Deleted set $set"));
	push(@$html,$cgi->h2("<a href=" . $cgi->url(-relative => 1) . "?user=".$cgi->param('user').">Return to Assignment Sets</a>"));
    }
    else
    {
	push(@$html,$cgi->h1("Delete Failed: set $set does not exist"));
    }
}

sub accept_set {
    my($fig,$cgi,$html) = @_;

    my $user = $cgi->param('user');
    my $set  = $cgi->param('set');
    my @flds = split(/:/,$set);
    my $who = $flds[4];
	
    if ($user)
    {
	my $userR = $user;
	if ($userR =~ s/^master://)
	{
	    $who = "master:$who";
	}
	
	if (system("$FIG_Config::bin/fig assign_functionF $who $FIG_Config::data/Assignments/$userR/$set > /dev/null") == 0)
	{
	    push(@$html,$cgi->h2("Made Assignments from $set"));
	    my $dellink=&delete_link($cgi,$set); 
	    $dellink =~ s/>delete</>Delete</;
	    push(@$html,$cgi->h2("$dellink this Assignment Set from the pending assignments"));
	}
	else
	{
	    push(@$html,$cgi->h1("Call Support: some error occurred in accepting assignments from $FIG_Config::data/Assignments/$userR/$set"));
	}
    }
    else
    {
	push(@$html,$cgi->h1("Sorry, but you need to specify a user to accept assignments"));
    }
}
	
sub func_of {
    my($fig,$peg,$user) = @_;
    my $func;

    if ($user =~ /^master:/)
    {
	$func = $fig->function_of($peg,"master");
    }
    else
    {
	$func = $fig->function_of($peg,$user);
    }
    return $func;
}

sub delete_checked {
    my($fig,$cgi,$html) = @_;
    my($line);

    my $user = $cgi->param('user');
    my $set  = $cgi->param('set');
    my @checked = $cgi->param('checked');
    my %checked = map { $_ => 1 } @checked;

    if ($user)
    {
	my $userR = $user;
	$userR =~ s/^master://;
	if (-s "$FIG_Config::data/Assignments/$userR/$set")
	{
	    if (rename("$FIG_Config::data/Assignments/$userR/$set","$FIG_Config::data/Assignments/$userR/$set~"))
	    {
		if (open(IN,"<$FIG_Config::data/Assignments/$userR/$set~") &&
		    open(OUT,">$FIG_Config::data/Assignments/$userR/$set"))
		{
		    while (defined($line = <IN>))
		    {
			if (($line =~ /^(\S+)/) && (! $checked{$1}))
			{
			    print OUT $line;
			}
		    }
		    close(IN);
		    close(OUT);

		    if (chmod(0777,"$FIG_Config::data/Assignments/$userR/$set"))
		    {
			unlink("$FIG_Config::data/Assignments/$userR/$set~");
			push(@$html,$cgi->h1("ok"));
		    }
		    else
		    {
			push(@$html,$cgi->h1("chmod failure: permissions problem"));
		    }
		}
		else
		{
		    push(@$html,$cgi->h1("could not open $FIG_Config::data/Assignments/$userR/$set; maybe a permissions problem"));
		}
	    }
	    else
	    {
		push(@$html,$cgi->h1("Could not rename $FIG_Config::data/Assignments/$userR/$set"));
	    }
	}
    }
    else
    {
	push(@$html,$cgi->h1("invalid user"));
    }
}
