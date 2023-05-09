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

package AliTree;

use strict;
use FIG;
use SameFunc;
use gjoseqlib;
use gjoalignment;
use tree_utilities;
use PHOB;
use Tracer;
use AliTrees;

use Carp;
use Data::Dumper;


#### To turn on tracing, at the command line type
###
###  export TRACING=Ross
###  trace 3 AliTree
###

sub new {
    my($class,$id,$fig,$data) = @_;

    ($id =~ /^\d+\.\d+\.peg\.\d+/) || confess "invalid id: $id";
    if (! defined($fig)) { $fig = new FIG }
    if (! defined($data))
    {
	if (-d "$FIG_Config::data/AlignmentsAndTrees")
	{
	    $data = "$FIG_Config::data/AlignmentsAndTrees";
	}
	else
	{
	    confess "Where are the alignments and trees?";
	}
    }

    my $ali_tree      = {};
    $ali_tree->{id}   = $id;
    $ali_tree->{fig}  = $fig;
    $ali_tree->{data} = $data;
    my $dir = $ali_tree->{dir}  = "$data/Library/$id";

    if (! defined("$dir/full.ali"))   { return undef }

    my($ali,$core_ali);
    open(ALI,"<$dir/full.ali") || die "could not open $dir/full.ali";
    ($ali = &gjoseqlib::read_fasta(\*ALI)) || die "$dir/full.ali is not well-formatted fasta";
    close(ALI);

    if (open(ALI,"<$dir/core.ali") && ($core_ali = &gjoseqlib::read_fasta(\*ALI)))
    {
	close(ALI);
    }
    else
    {
	$core_ali = undef;
    }
    my @deleted = grep {$fig->is_deleted_fid($_->[0]) } @$ali;

    my %deleted;
    if (@deleted > 0)
    {
	%deleted = map { $_->[0] => 1 } @deleted;
	$ali      = [grep { ! $deleted{$_->[0]} } @$ali];
	$core_ali = $core_ali ? [grep { ! $deleted{$_->[0]} } @$core_ali] : undef;
    }

    if (@$ali < 2)         { return undef }

    my @coords = ();
    if (open(COORDS,"<$dir/coords"))
    {
	@coords = map { chomp; [split(/\t/,$_)] } <COORDS>;
	close(COORDS);
    }

    if (@coords > @$ali)
    {
	@coords = grep { ! $deleted{$_->[0]} } @coords;
	open(COORDS,">$dir/coords") || die "could not update $dir/coords";
	foreach my $x (@coords)
	{
	    print COORDS join("\t",@$x),"\n";
	}
	close(COORDS);
    }
    elsif (@coords < @$ali)
    {
	open(COORDS,">$dir/coords") || die "could not update $dir/coords";
	for (my $tupleI = (@$ali - 1); ($tupleI >= 0); $tupleI--)
	{
	    my $tuple = $ali->[$tupleI];
	    my($peg,undef,$seq) = @$tuple;
	    $seq =~ s/-//g;
	    $seq = lc $seq;
	    my $full_seq = lc $fig->get_translation($peg);
	    my($offset,$n);
	    if (($offset = index($full_seq,$seq)) >= 0)
	    {
		print COORDS join("\t",($peg,$offset+1,$offset + length($seq),length($full_seq))),"\n";
		push(@coords,[$peg,$offset+1,$offset + length($seq),length($full_seq)]);
	    }
	    elsif (($n = int(0.4 * length($full_seq))) &&
		   (($offset = index($full_seq,substr($seq,$n))) >= 0))
	    {
		$offset -= $n;
		print COORDS join("\t",($peg,$offset+1,$offset + length($seq),length($full_seq))),"\n";
		push(@coords,[$peg,$offset+1,$offset + length($seq),length($full_seq)]);
	    }
	    else
	    {
		push(@deleted,$peg);
		print STDERR "SERIOUS ERROR: ",&Dumper($peg,$seq,$full_seq);
		splice(@$ali,$tupleI,1);
	    }
	}
	close(COORDS);
    }

    if (@deleted > 0)
    {
	open(ALI,">$dir/full.ali") || die "could not update $dir/full.ali";
	&gjoseqlib::print_alignment_as_fasta(\*ALI,$ali);
	close(ALI);

	if ($core_ali && (@$core_ali > 1) && open(ALI,">$dir/core.ali"))
	{
	    &gjoseqlib::print_alignment_as_fasta(\*ALI,$core_ali);
	    close(ALI);
	}
    }
    $ali_tree->{ali} = $ali;
    ############# we now have an up-to-date alignment ##############

    my %coords = map { $_->[0] => [$_->[1],$_->[2],$_->[3]] } @coords;
    $ali_tree->{coords} = \%coords;
    ############# we now have up-to-date coords ##############

     my $tree = "";
#    if ((! -s "$dir/tree.newick") && (@$ali > 3))
#    {
#	&FIG::run("make_neigh_joining_tree -a 2 $dir/full.ali > $dir/tree.newick");
#    }

    if ((@$ali > 3) && (-s "$dir/tree.newick"))
    {
	$tree = &tree_utilities::parse_newick_tree(join("",`cat $dir/tree.newick`));
	if (@deleted > 0)
	{
	    my $ids = &tree_utilities::tips_of_tree($tree);

	    if (@$ids > @$ali)
	    {
		my %good = map {$_->[0] => 1} @$ali;
		$tree    = &tree_utilities::subtree($tree,\%good);
		open(TREE,">$dir/tree.newick") 
		    || die "could not update $dir/tree.newick";
		print TREE &tree_utilities::to_newick($tree),"\n";
		close(TREE);
	    }
	}
    }
    $ali_tree->{tree} = $tree;
    ############# we now have an up-to-date tree ##############

    bless $ali_tree,$class;
    return $ali_tree;
}

sub tree {
    my($self) = @_;

    if (! $self->{tree})
    {
	my $id     = $self->{id};
	my $data   = $self->{data};
	my $dir    = $self->{dir};
	my $ali    = $self->{ali};
	if ((! -s "$dir/tree.newick") && (@$ali > 3))
	{
	    &FIG::run("make_neigh_joining_tree -a 2 $dir/full.ali > $dir/tree.newick");
	    $self->{tree} = &tree_utilities::parse_newick_tree(join("",`cat $dir/tree.newick`));
	}
    }
    return $self->{tree};
}

sub id {
    my($self) = @_;

    return $self->{id};
}

sub ali {
    my($self) = @_;
    
    return $self->{ali};
}

sub pegs_in_alignment {
    my($self) = @_;

    return $self->{coords};
}

sub functions_in {
    my($self) = @_;
    my $fig    = $self->{fig};

    my($pegH,$peg,%funcs);
    $pegH = $self->{coords};
    foreach $peg (keys(%$pegH))
    {
	my $func = $fig->function_of($peg);
	$funcs{$func}++;
    }
    return map { [$funcs{$_},$_] } sort { $funcs{$b} <=> $funcs{$a} } keys(%funcs);
}

sub display {
    my($self) = @_;

    my @lines = ();
    my $ali = $self->{ali};
    foreach my $tuple (@$ali)
    {
	push(@lines,sprintf("%32s",$tuple->[0]) . "\t" . $tuple->[2] . "\n");
    }
    return join("",@lines);
}

sub indel_ratio {
    my($self) = @_;

    my $seq = join("",map { $_->[2] } @{$self->{ali}});
    my $tot = length($seq);
    my $indels = ($seq =~ tr/-//);
    my $inrat = sprintf "%.3f", $indels/$tot;
    return $inrat;
}

sub overlaps {
    my($self) = @_;

    my $id     = $self->{id};
    my $fig    = $self->{fig};
    my $data   = $self->{data};
    my $coords = $self->{coords};
    my @pegs   = keys(%$coords);

    my $ali_trees = new AliTrees($fig,$data);
    my $overlaps = {};
    my($peg,@poss,$ali2,$id2,$coords2,%seen,@overlap);
    my($peg1,$c1,$c2,$b1,$e1,$b2,$e2,$ln1,$ln2,$ov);
    foreach $peg (@pegs)
    {
	@poss   = $ali_trees->alignments_containing_peg($peg);
	foreach $id2 (@poss)
	{
	    if (($id2 ne $id) && (! $seen{$id2}))
	    {
		$ali2 = new AliTree($id2,$fig,$data);
		$coords2 = $ali2->coords_of;
		@overlap = ();
		foreach $peg1 (@pegs)
		{
		    if (($c1 = $coords->{$peg1}) && ($c2 = $coords2->{$peg1}))
		    {
			($b1,$e1) = @$c1;
			($b2,$e2) = @$c2;
			$ln1 = ($e1-$b1)+1;
			$ln2 = ($e2-$b2)+1;
			$ov = &FIG::min($e1,$e2) - &FIG::max($b1,$b2);
			if (($ov > (0.9 * $ln1)) && ($ov > (0.9 * $ln2)))
			{
			    push(@overlap,[$peg1,$b1,$e1,$b2,$e2]);
			}
		    }
		}

		if (@overlap > 0)
		{
		    $overlaps->{$id2} = [sort { &FIG::by_fig_id($a,$b) } @overlap];
		}
		$seen {$id2} = 1;
	    }
	}
    }
    return $overlaps;
}
 
sub coords_of {
    my($self,$peg) = @_;

    return $peg ? $self->{coords}->{$peg} : $self->{coords};
}

sub sz {
    my($self) = @_;
    my $n = @{$self->{ali}};
    return $n;
}


sub html {
    my($self) = @_;

    my $id     = $self->{id};
    my $data   = $self->{data};
    my $dir    = "$data/$id";

    if ((! -s "$dir/full.html") && (-s "$dir/full.ali"))
    {
	&FIG::run("alignment_to_html < $dir/full.ali > $dir/full.html");
    }
    return (-s "$dir/full.html") ? join("",`cat $dir/full.html`) : undef;
}

sub phob_dir {
    my($self) = @_;

    my $dir    = $self->{dir};
    if (! -d "$dir/PHOB")
    {
	if ($self->make_phob_dir("$dir/PHOB"))
	{
	    return "$dir/PHOB";
	}
	else
	{
	    return "";
	}
    }
    else
    {
	return "$dir/PHOB";
    }
}

sub make_phob_dir {
    my($self,$dir) = @_;

    if (-d $dir) 
    {
	print STDERR "Attempt to make $dir failed: it already exists\n";
	return 0;
    }
    &FIG::verify_dir($dir);

    my($ali,$tree);
    if (($ali = $self->ali) && ($tree = $self->tree))
    {
	my($n,$to,$id,$seq,$idN,$tuple);
	open(IDS,">$dir/ids")       || die "could not open $dir/ids";
	open(ALI,">$dir/aln.fasta") || die "could not open $dir/aln.fasta";
	open(TREE,">$dir/tree.dnd") || die "could not open $dir/tree.dnd";
	$n = 1;
	$to = {};
	foreach $tuple (@$ali)
	{
	    ($id,undef,$seq) = @$tuple;
	    $idN = "id$n";
	    $n++;
	    print IDS "$idN\t$id\n";
	    $to->{$id} = $idN;
	    $seq =~ s/\s//gs;
	    $seq =~ s/[uU]/x/g;
	    &FIG::display_id_and_seq($idN,\$seq,\*ALI);
	}
	&tree_utilities::relabel_nodes($tree,$to);
	print TREE &tree_utilities::to_newick($tree),"\n";
	close(IDS);
	close(ALI);
	close(TREE);
	return 1;
    }
    else
    {
	return 0;
    }
}

1;
