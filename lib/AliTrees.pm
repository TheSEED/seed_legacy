# -*- perl -*-
########################################################################
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
########################################################################

package AliTrees;

use strict;
use FIG;
use Data::Dumper;
use DBrtns;
use Carp;
use AliTree;
use FIG;

# This is the constructor.  Presumably, $class is 'AliTrees'.  
#

sub new {
    my($class,$fig,$data) = @_;

    my $ali_trees = {};
    
    $ali_trees->{fig} = defined($fig->{_fig}) ? $fig->{_fig} : $fig;

    if (! defined($data))
    {
	if (-d "$FIG_Config::data/AlignmentsAndTrees")
	{
	    $data = "$FIG_Config::data/AlignmentsAndTrees";
	}
	else
	{
	    warn "Where are the alignments and trees?";
	    return undef;
	}
    }

    $ali_trees->{data} = $data;

    bless $ali_trees,$class;
    return $ali_trees;
}

sub all_alignments {
    my($self) = @_;

    my $fig = $self->{fig};
    my $dbh = $fig->db_handle;
    if (! $dbh->table_exists('alignments')) { return () }

    my $res = $dbh->SQL("SELECT DISTINCT ali_id from alignments");
    return sort map { $_->[0] } @$res;
}

sub alignments_containing_peg {
    my($self,$peg) = @_;

    my $fig = $self->{fig};
    my $dbh = $fig->db_handle;

    if (! $dbh->table_exists('alignments')) { return () }

    my $res = $dbh->SQL("SELECT DISTINCT ali_id from alignments WHERE peg = '$peg'");
    return sort map { $_->[0] } @$res;
}

sub delete_ali {
    my($self,$ali) = @_;

    if (! -d "$self->{data}\/Library/$ali") { return 0 }
    my $data = $self->{data};
    my $fig = $self->{fig};
    my $dir = "$data/Library/$ali";
    &FIG::verify_dir("$data/Deleted");
    my $dbh = $fig->db_handle;
    if (-d "$data/Deleted/$ali") { system "/bin/rm -rf $data/Deleted/$ali" }
    return ($dbh->SQL("DELETE FROM alignments WHERE ali_id = '$ali'") &&
	    (system("mv $dir $data/Deleted") == 0));
}

sub add_ali {
    my($self,$dir_to_add) = @_;

    my $data = $self->{data};
    my $fig  = $self->{fig};
    my $dbh = $fig->db_handle;
    
    my $ali;
    if (($dir_to_add =~ /([^\/]+)$/) && 
	($ali = $1) &&
	(! -d "$data/Library/$ali") &&
	(-s "$dir_to_add/full.ali") &&
	(system("cp -r $dir_to_add $data/Library/$ali") == 0))
    {
	my $ali_tree = new AliTree($ali,$fig,$data);
	my $h = $ali_tree->pegs_in_alignment($ali_tree->id);
	foreach my $peg (sort { &FIG::by_fig_id($a,$b) } keys(%$h))
	{
	    $dbh->SQL("INSERT INTO alignments (ali_id,peg)  VALUES ('$ali','$peg')");
	}
	return 1;
    }
    return 0;
}

sub merge_ali {
    my($self,$id1,$id2) = @_;

    ($id1 =~ /^\d+\.\d+\.peg\.\d+(-(\d+))?$/)
	|| return undef;
    my $next_id = &next_id($self,$id1);
    
    my $data = $self->{data};
    my $ali1 = &gjoseqlib::read_fasta("$data/Library/$id1/full.ali");
    my $ali2 = &gjoseqlib::read_fasta("$data/Library/$id2/full.ali");
    my $ali3;
    if ($ali3 = &merge($ali1,$ali2))
    {
	my $tmpdir = "$FIG_Config::var/Temp";
	&FIG::verify_dir($tmpdir);
	mkdir("$tmpdir/$next_id") 
	    || confess "could not make $tmpdir/$next_id";
	open(ALI,">$tmpdir/$next_id/full.ali") 
	    || confess "could not open $tmpdir/$next_id/full.ali";
	&gjoseqlib::print_alignment_as_fasta(\*ALI,$ali3);
	close(ALI);
	if ($self->add_ali("$tmpdir/$next_id"))
	{
	    system "/bin/rm -r $tmpdir/$next_id";
	    return $next_id;
	}
    }
    return undef;
}

sub merge {
    my($ali1,$ali2) = @_;

    my $ln1 = length($ali1->[0]->[2]);
    my $ln2 = length($ali2->[0]->[2]);

    my $s;
    my %in1 = map { $s = $_->[2]; $_->[0] => $_->[2] } @$ali1;
    my %in2 = map { $s = $_->[2]; $_->[0] => $_->[2] } @$ali2;

    my %common = map { $_->[0] => 1 } grep { $in2{$_->[0]} } @$ali1;

    if (keys(%common) == 0)
    {
	return undef;
    }

    my($id,$maps_to,%offsets);
    foreach $id (keys(%common))
    {
	my($off1,$off2) = &offsets($in1{$id},$in2{$id});
	if (! defined($off1))
	{
	    my $s1 = $in1{$id};  $s1 =~ s/-//g;
	    my $s2 = $in2{$id};  $s2 =~ s/-//g;
	    print STDERR &Dumper($off1,$off2,$s1,$s2);
	    print STDERR  "Cannot merge these: probably multidomains that were trimmed: check $id\n";
	    return undef;
	}
	$offsets{$id} = [$off1,$off2];
    }

    foreach $id (keys(%common))
    {
	my $seq1 = $in1{$id};
	my $seq2 = $in2{$id};

	my($off1,$off2) = @{$offsets{$id}};
	my $i1 = &start($off1->[0],$seq1);
	my $i2 = &start($off2->[0],$seq2);

	while (($i1 < $ln1) && ($i2 < $ln2))
	{
	    while (($i1 < $ln1) && (substr($seq1,$i1,1) eq "-")) { $i1++ }
	    while (($i2 < $ln2) && (substr($seq2,$i2,1) eq "-")) { $i2++ }
	    if (($i1 < $ln1) && ($i2 < $ln2))
	    {
		if (($i1 > $off1->[0]) && 
		    ($i2 > $off2->[0]) &&
		    (uc substr($seq1,$i1,1) ne uc substr($seq2,$i2,1)))
		{
		    print STDERR &Dumper($seq1,$seq2,$i1,$i2,$off1,$off2);
		    die "Something is seriously wrong";
		}
		$maps_to->{$i1}->{$i2}++;
	    }
	    $i1++;
	    $i2++;
	}
    }
# At this point maps_to will map columns in alignment1 to columns in alignment2.
# Or, more precisely, it gives votes on how to map the columns.

    my $whole_map = &build_map($ln1,$ln2,$maps_to);
# whole_map has mapps from alignment1 to columns in the new alignment, and the same 
# for alignment2

    my $ali3 = &build_ali($ali1,$ali2,$whole_map,\%common);
    return $ali3;
}

sub offsets {
    my($seq1,$seq2) = @_;

    $seq1 =~ s/-//g;
    $seq2 =~ s/-//g;

    my($beg1,$beg2) = &find_offset($seq1,$seq2);
    if (! defined($beg1)) { return undef }
    
    my $rev_seq1 = reverse $seq1;
    my $rev_seq2 = reverse $seq2;
    my($end1,$end2) = &find_offset($rev_seq1,$rev_seq2);
    if (! defined($end1)) { return undef }

    ($end1,$end2) = (length($seq1) - ($end1+1),length($seq2) - ($end2+1));
    return ([$beg1,$end1],[$beg2,$end2]);
}
 
sub find_offset {
    my($seq1,$seq2) = @_;

    my $off1 = index($seq2,substr($seq1,1,20));
    my $off2 = index($seq1,substr($seq2,1,20));
    if (($off1 <= 0) && ($off2 <= 0))
    {
	return undef;
    }
    elsif (($off1 > 0) && ($off2 <= 0))
    {
	return (0,$off1-1);
    }
    elsif (($off2 > 0) && ($off1 <= 0))
    {
	return ($off2-1,0);
    }
    elsif (($off2 == 1) && ($off1 == 1))
    {
	return (0,0);
    }
    return undef;
}

sub start {
    my($off,$seq) = @_;

    my $i=0;
    while (($i < length($seq)) && (($off > 0) || (substr($seq,$i,1) eq "-"))) 
    { 
	if (substr($seq,$i,1) ne "-") { $off-- }
	$i++;
    }
    return $i;
}

sub build_map {
    my($ln1,$ln2,$maps_to) = @_;

    my $expanded_map = {};
    my @cols_connected = sort { $a <=> $b } keys(%$maps_to);

    my($n,$colI,$col,$h,@tuples,$tuple,$to);
    foreach $col (@cols_connected)
    {
	$h = $maps_to->{$col};
	my @poss = sort { ($h->{$b} <=> $h->{$a}) or ($a <=> $b) } keys(%$h);
	push(@tuples,[$col,$poss[0]]);
    }

    @tuples = &pins(\@tuples,10);
    foreach $tuple (@tuples)
    {
	($col,$to) = @$tuple;
	$expanded_map->{$col} = $to;
    }
    my @cols_connected = sort { $a <=> $b } keys(%$expanded_map);

    for ($colI=0; ($colI < (@cols_connected - 1)) && 
	          ($expanded_map->{$cols_connected[$colI]} < $expanded_map->{$cols_connected[$colI+1]});
         $colI++) {}

    
    if ($colI < (@cols_connected - 1))
    {
	print STDERR &Dumper($colI,$cols_connected[$colI],$colI+1,$cols_connected[$colI+1],
			     $expanded_map->{$cols_connected[$colI]},$expanded_map->{$cols_connected[$colI+1]}
			     );
	confess "mapping is inconsistent";
    }

    for ($colI=0; ($colI < (@cols_connected - 1)); $colI++)
    {
	if ((($n = ($cols_connected[$colI+1] - $cols_connected[$colI])) < 5) &&
	    (($expanded_map->{$cols_connected[$colI+1]} - $expanded_map->{$cols_connected[$colI]}) == $n))
	{
	    $n--;
	    while ($n > 0)
	    {
		$expanded_map->{$cols_connected[$colI]+$n} = $expanded_map->{$cols_connected[$colI]} + $n;
		$n--;
	    }
	}
    }

    my($map1,$map2,$i1,$i2,$i3);
    @cols_connected = sort { $a <=> $b } keys(%$expanded_map);
    $map1 = [];
    $map2 = [];
    $i1   = $cols_connected[0];
    $i2   = $expanded_map->{$cols_connected[0]};
    $i3   = 0;

    push(@$map1,[$i1,$i3]);    ### We begin processing adjacent pairs in mapping
    push(@$map2,[$i2,$i3]);    ### with the first coordinate of each pair "already processed"
    $i3++;

    my $j;
    for ($colI=0; ($colI < (@cols_connected-1)); $colI++)
    {
	$i1   = $cols_connected[$colI] + 1;
	$n    = $cols_connected[$colI+1] - $i1;
	for ($j=0; ($j < $n); $j++)
	{
	    push(@$map1,[$i1+$j,$i3]);
	    $i3++;
	}

	$i2   = $expanded_map->{$cols_connected[$colI]} + 1;
	$n    = $expanded_map->{$cols_connected[$colI+1]} - $i2;
	for ($j=0; ($j < $n); $j++)
	{
	    push(@$map2,[$i2+$j,$i3]);
	    $i3++;
	}

	push(@$map1,[$cols_connected[$colI+1],$i3]);
	push(@$map2,[$expanded_map->{$cols_connected[$colI+1]},$i3]);
	$i3++;
    }
    return [$i3,$map1,$map2];     # [length-of-merge,map-for-ali1,map-for-ali2]
}

sub build_ali {
    my($ali1,$ali2,$map,$common) = @_;

    my $ali3 = [];
    my($ln,$map1,$map2) = @$map;

    my($x,$entry);
    foreach $x (@$ali1)
    {
	$entry = &expand_entry($ln,$map1,$x);
	push(@$ali3,$entry);
    }
    
    foreach $x (@$ali2)
    {
	if (! $common->{$x->[0]})
	{
	    $entry = &expand_entry($ln,$map2,$x);
	    push(@$ali3,$entry);
	}
    }
    return $ali3;
}

sub expand_entry {
    my($ln,$map,$old_entry) = @_;

    my $seq     = "-" x $ln;
    my $old_seq = $old_entry->[2];
    my $tuple;
    foreach $tuple (@$map)
    {
	my($from,$to) = @$tuple;
	substr($seq,$to,1) = substr($old_seq,$from,1);
    }
    return [$old_entry->[0],"",$seq];
}

sub set_all {
    my($self) = @_;

    my $data = $self->{data};
    my $fig  = $self->{fig};

    my @all = $self->all_alignments;
    my($id,$ali);
    foreach $id (@all)
    {
	$ali = new AliTree($id,$fig,$data);
	undef $ali;
    }
}

sub load_db {
    my($self) = @_;

    my $data = $self->{data};
    my $fig  = $self->{fig};

    my $dbf = $fig->db_handle;
    $dbf->drop_table( tbl => 'alignments' );
    $dbf->create_table( tbl => 'alignments', 
			flds => 'ali_id  varchar(32), peg varchar(32)'
                      );

    my $tmpdir = "$FIG_Config::var/Temp";
    &FIG::verify_dir($tmpdir);
    open(OUT,">$tmpdir/alignments.$$") || die "could not open $tmpdir/alignments.$$";
    opendir(DIR,"$data/Library") || die "could not open $data";
    my @alis = grep { $_ !~ /^\./ } readdir(DIR);
    closedir(DIR);
    foreach my $ali (@alis)
    {
	my @pegs = map { ($_ =~ /^(fig\|\d+\.\d+\.peg\.\d+)/) ? $1 : () } `cut -f1  $data/Library/$ali/coords`;
	foreach my $peg (@pegs)
	{
	    print OUT "$ali\t$peg\n";
	}
    }
    close(OUT);
    $dbf->load_table( tbl => "alignments", file => "$tmpdir/alignments.$$");
    unlink("$tmpdir/alignments.$$");

    $dbf->create_index( idx  => "alignments_id_ix",
			tbl  => "alignments",
			type => "btree",
			flds => "ali_id" );
    $dbf->create_index( idx  => "alignments_peg_ix",
			tbl  => "alignments",
			type => "btree",
			flds => "peg" );
}

sub next_id {
    my($self,$id) = @_;

    my $x;
    $id =~ s/\-\d+$//;
    my @id_derivatives = grep { ($_ =~ /^(\d+\.\d+\.peg\.\d+)(-(\d+))?$/) && ($1 eq $id) } $self->all_alignments;
    my $n = 1;
    foreach $x (@id_derivatives)
    {
	if (($x =~ /\-(\d+)$/) && ($n <= $1)) { $n = $1 + 1; }
    }
    return "$id-$n";
}

sub pins {
    my($tuples,$run_dist) = @_;

    my @grouped = &group($tuples,$run_dist);
    my $i = $#grouped;
    while ($i > 0)
    {
	while (($i > 0) &&
	       ($i < @grouped) && 
	       &cross($grouped[$i-1],$grouped[$i]))
	{
	    my $n1 = @{$grouped[$i-1]};
	    my $n2 = @{$grouped[$i]};
	    if ($n1 < $n2)
	    {
		pop(@{$grouped[$i-1]});
		if ($n1 == 1)
		{
		    splice(@grouped,$i-1,1);
		    $i--;
		}
	    }
	    else
	    {
		pop(@{$grouped[$i]});
		if ($n2 == 1)
		{
		    splice(@grouped,$i,1);
		}
	    }
	}
	$i--;
    }
    my @left = ();
    my $group;
    foreach $group (@grouped)
    {
	push(@left,@$group);
    }
    return @left;
}

sub cross {
    my($g1,$g2) = @_;

    my($x,$y,$b1,$e1,$b2,$e2);
    if ((@$g1 > 0) && (@$g2 > 0))
    {
	$x = $g1->[@$g1 - 1];
	$y = $g2->[0];
	($b1,$e1) = @$x;
	($b2,$e2) = @$y;
	return ((($b1 <= $b2) && ($e1 >= $e2)) ||
		(($b1 >= $b2) && ($e1 <= $e2)));
    }
    return 0;
}

sub group {
    my($tuples,$run_dist) = @_;

    my @groups = ();
    my($i,$group);
    $i = 0;
    while ($i < @$tuples)
    {
	my $group = [$tuples->[$i]];
	$i++;
	while (($i < @$tuples) &&
	       ($tuples->[$i]->[0] <= ($group->[$#{$group}]->[0] + $run_dist)) &&
	       ($tuples->[$i]->[1] <= ($group->[$#{$group}]->[1] + $run_dist)) &&
	       ($tuples->[$i]->[1] >  $group->[$#{$group}]->[1]))
	{
	    push(@$group,$tuples->[$i]);
	    $i++;
	}
	push(@groups,$group);
    }
    return @groups;
}
	
1;
