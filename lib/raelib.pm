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

# -*- perl -*-

=pod

=head1 RAE Library

 Some routines and things that Rob uses. Please feel free to use at will and incorporate into
 your own code or move them into FIG.pm or elsewhere.

 For questions about this email RobE@theFIG.info

=cut

package raelib;
use strict;
use Bio::SeqIO;
use Bio::Seq;
use Bio::Tools::SeqStats;
use Bio::SeqFeature::Generic;

# we don't know whether the Spreadsheet::WriteExcel methods are available on all systems, and even on the CI systems they are currently in my shared directory
# so we use an eval and set the boolean if we are cool.
my $useexcel;
my $excelfile;
my $excelfilelink="";
BEGIN {
    eval "use Spreadsheet::WriteExcel";
    unless ($@) {$useexcel=1}
}

END {
    my $self=shift;
    if ($useexcel && $excelfile) {&close_excel_file($excelfile)}
}


use FIG;
my $fig=new FIG;

=head2 Methods

=head3 new

Just instantiate the object and return $self

=cut

sub new {
 my ($class)=@_;
 my $self={};
 $self->{'useexcel'}=1 if ($useexcel);
 return bless $self, $class;
}
   



=head3 features_on_contig

 Returns a reference to an array containing all the features on a contig in a genome.
 
 use: 

 my $arrayref=$rae->features_on_contig($genome, $contig);

 or
 
 foreach my $peg (@{$rae->features_on_contig($genome, $contig)}) {
  ... blah blah ...
 }

 returns undef if contig is not a part of genome or there is nothing to return, otherwise returns a list of pegs
 
 v. experimental and guaranteed not to work!

=cut

sub features_on_contig {
 my ($self, $genome, $contig)=@_;
 # were this in FIG.pm you'd use this line:
 #my $rdbH = $self->db_handle;

 my $rdbH = $fig->db_handle;
 my $relational_db_response=$rdbH->SQL('SELECT id FROM features WHERE  (genome = \'' . $genome . '\' AND  location ~* \'' . $contig . '\')');
 # this is complicated. A reference to an array of references to arrays, and we only want the first element. 
 # simplify.
 my @results;
 foreach my $res (@$relational_db_response) {push @results, $res->[0]}
 return \@results;
}


=head2 pegs_in_order

Given a genome id, returns a list of the pegs in order along the genome. 

my @pegs_in_order = $rae->pegs-in_order($genome);

This code is actually taken from adjacent.pl but put here to be useful

=cut

sub pegs_in_order {
	my ($self, $genome) = @_;
        my @pegs = map  { $_->[0] }
        sort { ($a->[1] cmp $b->[1]) or ($a->[2] <=> $b->[2]) }
        map  { my $peg = $_;
                if (my $loc = $fig->feature_location($peg) )
                {
                        my ($contig,$beg,$end) = $fig->boundaries_of($loc);
                        [$peg,$contig,&FIG::min($beg,$end)];
                }
                else
                {
                        ();
                }
        }
        $fig->pegs_of($genome);
        return @pegs;
}

=head3 mol_wt

Calculate the molecular weight of a protein.

This just offlaods the calculation to BioPerl, which is probably dumb since we need to load the whole of bioperl in just for this, but I don't have time to rewrite their method now, and I am not going to copy and paste it since I didn't write it :)

my ($lower, $upper)=$raelib->mol_wt($peg);

$lower is the lower bound for the possible mw, upper is the upper bound.

=cut

sub mol_wt {
    my ($self, $fid)=@_;
    my $sobj=Bio::Seq->new(-seq => $fig->get_translation($fid), -id => $fid);
    return Bio::Tools::SeqStats->get_mol_wt($sobj);
}


=head3 pirsfcorrespondence

Generate the pirsf->fig id correspondence. This is only done once and the correspondence file is written. This is so that we can easily go back and forth.

The correspondence has PIR ID \t FIG ID\n, and is probably based on ftp://ftp.pir.georgetown.edu/pir_databases/pirsf/data/pirsfinfo.dat

This method takes three arguments:
   from    : pirsfinfo.dat file
   to      : file to write information to
   verbose : report on progress 

Note that if the from filename ends in .gz it assumed to be a gzipped file and will be opened accordingly.

Returns the number of lines in the pirsinfo file that were read.

=cut

sub pirsfcorrespondence { 
 my ($self, $from, $to, $verbose)=@_;
 unless (-e $from) {
  print STDERR "File $from does not exist as called in $0\n";
  return 0;
 }
 if ($from =~ /\.gz$/) {
  open(IN, "|gunzip -c $from") || die "Can't open $from using a gunzip pipe";
 }
 else {
  open (IN, $from) || die "Can't open $from";
 }
 open (OUT, ">$to") || die "Can't write to $to";
 my $linecount;
 while (<IN>) {
  $linecount++;
  if ($verbose && !($linecount % 10000))  {print STDERR "Parsed $linecount lines\n"}
  if (/^>/) {print OUT; next}
  chomp;
  foreach my $peg ($self->swiss_pir_ids($_)) {
   print OUT $_, "\t", $peg, "\n";
  }
 }
 close IN;
 close OUT;
 return $linecount;
}

=head3 uniprotcorrespondence

Generate a correspondence table between uniprot knowledge base IDs and FIG ID's.

The uniprot KB file is in the form:  UniProtKB_Primary_Accession | UniProtKB_ID | Section | Protein Name

 This method takes three arguments:
   from    : uniprotKB file
   to      : file to write information to
   verbose : report on progress 

Note that if the from filename ends in .gz it assumed to be a gzipped file and will be opened accordingly.

 Returns the number of lines in the uniprotkb file that were read.

=cut

sub uniprotcorrespondence {
 my ($self, $from, $to, $verbose)=@_;
 unless (-e $from) {
  print STDERR "File $from does not exist as called in $0\n";
  return 0;
 }
 if ($from =~ /\.gz$/) {
  open(IN, "|gunzip -c $from") || die "Can't open $from using a gunzip pipe";
 }
 else {
  open (IN, $from) || die "Can't open $from";
 }
 open (OUT, ">$to") || die "Can't write to $to";
 my $linecount;
 while (<IN>) {
  chomp;
  $linecount++;
  if ($verbose && !($linecount % 10000))  {print STDERR "Parsed $linecount lines\n"}
  my @line=split /\s+\|\s+/;
  my $added;
  foreach my $peg ($self->swiss_pir_ids($line[0])) {
   print OUT "$_ | $peg\n";
   $added=1;
  }
  unless ($added) {print OUT "$_\n"}
 }
 close IN;
 close OUT;
 return $linecount;
}

=head3 prositecorrespondence

Generate a correspondence table between prosite and seed using sp id's and seed ids.

The SwissProt prosite file is from ftp://ca.expasy.org/databases/prosite/release_with_updates/prosite.dat and is in horrible swiss prot format, so we'll parse out those things that we need and put them in the file

The output file will have the following columns:

prosite family accession number, prosite family name, family type, swiss-prot protein id, fig protein id.

The family type is one of rule, pattern, or matrix. Right now (Prosite Release 19.2 of 24-May-2005) there are 4 rules, 1322 patterns, and 521 matrices.

 This method takes three arguments:
   from    : prosite file
   to      : file to write information to
   verbose : report on progress 

Note that if the from filename ends in .gz it assumed to be a gzipped file and will be opened accordingly.

 Returns the number of lines in the prosite file that were read.

=cut

sub prositecorrespondence {
 my ($self, $from, $to, $verbose)=@_;
 unless (-e $from) {
  print STDERR "File $from does not exist as called in $0\n";
  return 0;
 }
 if ($from =~ /\.gz$/) {
  open(IN, "|gunzip -c $from") || die "Can't open $from using a gunzip pipe";
 }
 else {
  open (IN, $from) || die "Can't open $from";
 }
 open (OUT, ">$to") || die "Can't write to $to";
 my $linecount;
 my ($famac, $famname, $famtype)=('','',''); 
 while (<IN>) {
  chomp;
  $linecount++;
  if ($verbose && !($linecount % 10000))  {print STDERR "Parsed $linecount lines\n"}
  if (m#//#) {($famac, $famname, $famtype)=('','',''); next}
  elsif (m/^ID\s*(.*?);\s*(\S+)/) {($famname, $famtype)=($1, $2); next}
  elsif (m/^AC\s*(\S+)/) {$famac=$1; $famac =~ s/\;\s*$//; next}
  next unless (m/^DR/); # ignore all the other crap in the prosite file for now. Note we might, at some point, want to grab all that, but that is for another time.
  #
  # this is the format of the DR lines:
  # DR   P11460, FATB_VIBAN , T; P40409, FEUA_BACSU , T; P37580, FHUD_BACSU , T;
  s/^DR\s*//;
  foreach my $piece (split /\s*\;\s*/, $_) {
   my ($acc, $nam, $unk)=split /\s*\,\s*/, $piece;
   foreach my $fig ($self->swiss_pir_ids($acc)) {
    print OUT join "\t", ($famac, $famname, $famtype, $acc, $fig), "\n";
   }
  }
 }
}

=head3 swiss_pir_ids()

SwissProt/PIR have lots of ID's that we want to get, usually in this order - uni --> tr --> sp. This routine will map swissprot/pir ids to fig id's, and return an array of FIG id's that match the ID.

=cut

sub swiss_pir_ids {
 my ($self, $id)=@_;
 return () unless ($id);
 $id =~ s/^\s+//; $id =~ s/\s+$//; # trim off the whitespace
 
 my @return=($fig->by_alias("uni|$id"));
 return @return if ($return[0]);
 
 @return=($fig->by_alias("tr|$id"));
 return @return if ($return[0]);

 @return=($fig->by_alias("sp|$id"));
 return @return if ($return[0]);
 
 return ();
}

=head3 ss_by_id

 Generate a list of subsystems that a peg occurs in. This is a ; separated list.
 This is a wrapper that removes roles and ignores essential things

=cut

sub ss_by_id { 
 my ($self, $peg)=@_;
 my $ssout;
 foreach my $ss (sort $fig->subsystems_for_peg($peg)) 
 {
  next if ($$ss[0] =~ /essential/i); # Ignore the Essential B-subtilis subsystems
  $ssout.=$$ss[0]."; ";
 }
 $ssout =~ s/; $//;
 return $ssout;
}

=head3 ss_by_homol

 Generate a list of subsystems that homologs of a peg occur in. This is a ; separated list.
 This is also a wrapper around sims and ss, but makes everything unified

=cut

sub ss_by_homol {
 my ($self, $peg)=@_;
 return unless ($peg);
 my ($maxN, $maxP)=(50, 1e-20);

 # find the sims
 my @sims=$fig->sims($peg, $maxN, $maxP, 'fig');

 # we are only going to keep the best hit for each peg
 # in a subsystem
 my $best_ss_score; my $best_ss_id;
 foreach my $sim (@sims)
 {
  my $simpeg=$$sim[1];
  my $simscore=$$sim[10];
  my @subsys=$fig->subsystems_for_peg($simpeg);
  foreach my $ss (@subsys)
  {
   if (! defined $best_ss_score->{$$ss[0]}) {$best_ss_score->{$$ss[0]}=$simscore; $best_ss_id->{$$ss[0]}=$simpeg}
   elsif ($best_ss_score->{$$ss[0]} > $simscore)
   {
    $best_ss_score->{$$ss[0]}=$simscore;
    $best_ss_id->{$$ss[0]}=$simpeg;
   }
  }
 }

 my $ssoutput=join "", (map {"$_ (".$best_ss_id->{$_}."), "} keys %$best_ss_id);

 $ssoutput =~ s/, $//;
 return $ssoutput;
}

=head3 tagvalue

 This will just check for tag value pairs and return either an array of values or a single ; separated list (if called as a scalar)
 
 e.g. $values=raelib->tagvalue($peg, "PIRSF"); print join "\n", @$values;
 
 Returns an empty array if no tag/value appropriate.

 Just because I use this a lot I don't want to waste rewriting it. 

=cut

sub tagvalue {
 my ($self, $peg, $tag)=@_;
 my @return;
 my @attr=$fig->feature_attributes($peg);
 foreach my $attr (@attr) { 
  my ($gotpeg, $gottag, $val, $link)=@$attr;
  push @return, $val if ($gottag eq $tag);
 }
 return wantarray ? @return : join "; ", @return;
}

=head3 locations_on_contig

Return the locations of a sequence on a contig.

This will look for exact matches to a sequence on a contig, and return a reference to an array that has all the locations.

my $locations=$raelib->locations_on_contig($genome, $contig, 'GATC', undef);
foreach my $bp (@$locations) { ... do something ... }

first argument  : genome number
second argument : contig name
third argument  : sequence to look for
fourth argument : beginning position to start looking from (can be undef)
fifth argument  : end position to stop looking from (can be undef)
sixth argument : check reverse complement (0 or undef will check forward, 1 or true will check rc)

Note, the position is calculated before the sequence is rc'd

=cut

sub locations_on_contig {
 my ($self, $genome, $contig, $sequence, $from, $to, $check_reverse)=@_;
 my $return=[];
 
 # get the dna sequence of the contig, and make sure it is uppercase
 my $contig_ln=$fig->contig_ln($genome, $contig);
 return $return unless ($contig_ln);
 unless ($from) {$from=1}
 unless ($to) {$to=$contig_ln}
 if ($from > $to) {($from, $to)=($to, $from)}
 my $dna_seq=$fig->dna_seq($genome, $contig."_".$from."_".$to);
 $dna_seq=uc($dna_seq);

 # if we want to check the rc, we actually rc the query
 $sequence=$fig->reverse_comp($sequence) if ($check_reverse);
 $sequence=uc($sequence);

 # now find all the matches
 my $posn=index($dna_seq, $sequence, 0);
 while ($posn > -1) {
  push @$return, $posn;
  $posn=index($dna_seq, $sequence, $posn+1);
 }
 return $return;
}


=head3 scrolling_org_list

This is the list from index.cgi, that I call often. It has one minor modification: the value returned is solely the organisms id and does not contain genus_species information. I abstracted this here: 1, so I could call it often, and 2, so I could edit it once.

use like this push @$html, $raelib->scrolling_org_list($cgi, $multiple, $default, $limit);

multiple selections will only be set if $multiple is true 

default will set a default to override (maybe) korgs

limit is a reference to an array of organism IDs that you want to limit the list to.

=cut

sub scrolling_org_list {
 my ($self, $cgi, $multiple, $default, $limit)=@_;
 unless ($multiple) {$multiple=0}
 
 my @display = ( 'All', 'Archaea', 'Bacteria', 'Eucarya', 'Viruses', 'Environmental samples' );

 #
 #  Canonical names must match the keywords used in the DBMS.  They are
 #  defined in compute_genome_counts.pl
 #
 my %canonical = (
        'All'                   =>  undef,
        'Archaea'               => 'Archaea',
        'Bacteria'              => 'Bacteria',
        'Eucarya'               => 'Eukaryota',
        'Viruses'               => 'Virus',
        'Environmental samples' => 'Environmental Sample'
     );

 my $req_dom = $cgi->param( 'domain' ) || 'All';
 my @domains = $cgi->radio_group( -name     => 'domain',
                                     -default  => $req_dom,
                                     -override => 1,
                                     -values   => [ @display ]
                                );

 my $n_domain = 0;
 my %dom_num = map { ( $_, $n_domain++ ) } @display;
 my $req_dom_num = $dom_num{ $req_dom } || 0;

 #
 #  Viruses and Environmental samples must have completeness = All (that is
 #  how they are in the database).  Otherwise, default is Only "complete".
 #
 my $req_comp = ( $req_dom_num > $dom_num{ 'Eucarya' } ) ? 'All'
              : $cgi->param( 'complete' ) || 'Only "complete"';
 my @complete = $cgi->radio_group( -name     => 'complete',
                                   -default  => $req_comp,
                                   -override => 1,
                                    -values   => [ 'All', 'Only "complete"' ]
                       );
 #
 #  Use $fig->genomes( complete, restricted, domain ) to get org list:
 #
 my $complete = ( $req_comp =~ /^all$/i ) ? undef : "complete";
 
 my $orgs; my $label;
 @$orgs =  $fig->genomes( $complete, undef, $canonical{ $req_dom } );

 # limit the list of organisms to a selected few if required
 if ($limit)
 {
    my %lim=map {($_=>1)} @$limit;
    my $norg;
    foreach my $o (@$orgs) {push @$norg, $o if ($lim{$o})}
    $orgs=$norg;
}
 
 foreach (@$orgs) {
   my $gs = $fig->genus_species($_);
   if ($fig->genome_domain($_) ne "Environmental Sample")
   {
    my $gc=$fig->number_of_contigs($_);
    $label->{$_} = "$gs ($_) [$gc contigs]";
   }
   else
   {
    $label->{$_} = "$gs ($_) ";
   }
  }

 @$orgs = sort {$label->{$a} cmp $label->{$b}} @$orgs;

 my $n_genomes = @$orgs;

 return (         "<TABLE>\n",
                  "   <TR>\n",
                  "      <TD>",
	          $cgi->scrolling_list( -name     => 'korgs',
                                        -values   => $orgs,
					-labels   => $label,
                                        -size     => 10,
					-multiple => $multiple,
					-default  => $default,
                                      ), $cgi->br,
                  "$n_genomes genomes shown ",
                  $cgi->submit( 'Update List' ), $cgi->reset, $cgi->br,
                  "      </TD>",
                  "      <TD>",
                  join( "<br>", "<b>Domain(s) to show:</b>", @domains), "<br>\n",
                  join( "<br>", "<b>Completeness?</b>", @complete), "\n",
                  "</TD>",
                  "   </TR>\n",
                  "</TABLE>\n",
        );
}


=head3 scrolling_subsys_list

Create a scrolling list of all subsystems. Just like scrolling_org_list, this will make the list and allow you to select multiples.

use like this 

push @$html, $raelib->scrolling_subsys_list($cgi, $multiple);

=cut

sub scrolling_subsys_list {
 my ($self, $cgi, $multiple)=@_;
 $multiple=0 unless (defined $multiple);
 my @ss=sort {uc($a) cmp uc($b)} $fig->all_subsystems();
 my $label;
 # generate labels for the list
 foreach my $s (@ss) {my $k=$s; $k =~ s/\_/ /g; $k =~ s/  / /g; $k =~ s/\s+$//; $label->{$s}=$k}
 return $cgi->scrolling_list(
  -name    => 'subsystems',
  -values  => \@ss,
  -labels  => $label,
  -size    => 10,
  -multiple=> $multiple,
 );
}

=head3 subsys_names_for_display

Return a list of subsystem names for display. This will take a list as an argument and return a nice clean list for display.

$raelib->subsys_names_for_display(@ss);
or
$raelib->subsys_names_for_display($fig->all_subsystems());

=cut

sub subsys_names_for_display {
 my ($self, @ss)=@_;
 foreach (@ss) {s/\_/ /g; 1 while (s/  / /g); s/\s+$//}
 return @ss;
}

=head3 GenBank

 This object will take a genome number and return a Bio::Seq::RichSeq object that has the whole genome
 in GenBank format. This should be a nice way of getting some data out, but will probably be quite slow 
 at building the object.

 Note that you need to call this with the genome name and the contig. This will then go through that contig.

 Something like this should work

 foreach my $contig ($fig->all_contigs($genome)) {
  my $seqobj=FIGRob->GenBank($genome, $contig);
  # process the contig
 }
 
=cut

sub GenBank {
 my ($self, $genome, $contig)=@_;
 my $gs=$fig->genus_species($genome);
 return unless ($gs);
 unless ($contig) {
  print STDERR "You didn't provide a contig for $gs. I think that was a mistake. Sorry\n";
  return;
 }
 my $len=$fig->contig_ln($genome, $contig);
 unless ($len) {
  print STDERR "$contig from $gs doesn't appear to have a length. Is it right?\n";
  return;
 }


 # first find all the pegs ...
 my $features; # all the features in the genome
 my $allpegs; # all the pegs
 my $translation; # all the protein sequences
 foreach my $peg ($fig->pegs_of($genome)) {
  my @location=$fig->feature_location($peg);
  my $func=$fig->function_of($peg);
  foreach my $loc (@location) {
   $loc =~ /^(.*)\_(\d+)\_(\d+)$/;
   my ($cg, $start, $stop)=($1, $2, $3);
   next unless ($cg eq $contig); 
   # save this information for later
   $features->{'peg'}->{$loc}=$func;
   $allpegs->{'peg'}->{$loc}=$peg;
   $translation->{'peg'}->{$loc}=$fig->get_translation($peg);
  }
 }
 # ... and all the RNAs
 foreach my $peg ($fig->rnas_of($genome)) {
  my @location=$fig->feature_location($peg);
  my $func=$fig->function_of($peg);
  foreach my $loc (@location) {
   $loc =~ /^(.*)\_(\d+)\_(\d+)$/;
   my ($cg, $start, $stop)=($1, $2, $3);
   next unless ($cg eq $contig);
   # save this information for later
   $features->{'rna'}->{$loc}=$func;
   $allpegs->{'rna'}->{$loc}=$peg;
  }
 }


 # now get all the contigs out
 my $seq=$fig->dna_seq($genome, $contig."_1_".$len);
 my $description = "Contig $contig from " . $fig->genus_species($genome);
 my $sobj=Bio::Seq->new(
          -seq              =>  $seq, 
	  -id               =>  $contig, 
	  -desc             =>  $description, 
	  -accession_number =>  $genome
	  );
 foreach my $prot (keys %{$features->{'peg'}}) {
   $prot =~ /^(.*)\_(\d+)\_(\d+)$/;
   my ($cg, $start, $stop)=($1, $2, $3);
   my $strand=1;
   if ($stop < $start) {
    ($stop, $start)=($start, $stop);
    $strand=-1;
 }
  
 my $feat=Bio::SeqFeature::Generic->new(
        -start         =>  $start,
        -end           =>  $stop,
        -strand        =>  $strand,
        -primary       =>  'CDS',
	-display_name  =>  $allpegs->{'peg'}->{$prot},
	-source_tag    =>  'the SEED',
        -tag           =>  
                       {
                       db_xref     =>   $allpegs->{'peg'}->{$prot},
		       note        =>  'Generated by the Fellowship for the Interpretation of Genomes',
                       function    =>  $features->{'peg'}->{$prot},
		       translation =>  $translation->{'peg'}->{$prot}
		      }
       );
 
   $sobj->add_SeqFeature($feat);
 }
 
 foreach my $prot (keys %{$features->{'rna'}}) {
   $prot =~ /^(.*)\_(\d+)\_(\d+)$/;
   my ($cg, $start, $stop)=($1, $2, $3);
   my $strand=1;
   if ($stop < $start) {
    ($stop, $start)=($start, $stop);
    $strand=-1;
   }
  
   my $feat=Bio::SeqFeature::Generic->new(
        -start         =>  $start,
        -end           =>  $stop,
        -strand        =>  $strand,
        -primary       =>  'RNA',
        -source_tag    =>  'the SEED',
        -display_name  =>  $allpegs->{'rna'}->{$prot},
        -tag           =>  
                      {
		       db_xref     =>   $allpegs->{'rna'}->{$prot},
                       note        =>  'Generated by the Fellowship for the Interpretation of Genomes',
                       function    =>  $features->{'rna'}->{$prot},
		      }
       );
 
  $sobj->add_SeqFeature($feat);
 }
 return $sobj;
}
 
=head3 best_hit

 Returns the FIG id of the single best hit to a peg

 eg

 my $bh=$fr->best_hit($peg);
 print 'function is ', scalar $fig->function_of($bh);

=cut 

sub best_hit {
 my ($self, $peg)=@_;
 return unless ($peg);
 
 my ($maxN, $maxP)=(1, 1e-5);
 my @sims=$fig->sims($peg, $maxN, $maxP, 'fig');
 return ${$sims[0]}[1];
}


=head3 read_fasta

Read a fasta format file and return a reference to a hash with the data. The key is the ID and the value is the sequence. If you supply the optional keep comments then the comments (anything after the first white space are returned as a sepaarte hash).

Usage:
my $fasta=$raelib->read_fasta($file);
my ($fasta, $comments)=$raelib->read_fasta($file, 1);

=cut

sub read_fasta {
 my ($self, $file, $keepcomments)=@_;
 if ($file =~ /\.gz$/) {open(IN, "gunzip -c $file|") || die "Can't open a pipe from gunzip -c $file"}
 elsif ($file =~ /.zip$/) {open(IN, "unzip -p $file|") || die "can't open a pipe from unzip -p $file"}
 else {open (IN, $file) || die "Can't open $file"}
 my %f; my $t; my $s; my %c;
 while (<IN>) {
  chomp;
  if (/^>/) {
   if ($s) {
    $f{$t}=$s;
    undef $s;
   }
   s/^>(\S+)\s*//;
   $t=$1;
   $c{$t}=$_ if ($_);
  }
  else {$s .= $_}
 }
 $f{$t}=$s;
 if ($keepcomments) {return (\%f, \%c)} 
 else {return \%f}
}

=head3 rc

Reverse complement. It's too easy.

=cut

sub rc {
 my ($self, $seq)=@_;
 $seq =~ tr/acgtrymkbdhvACGTRYMKBDHV/tgcayrkmvhdbTGCAYRKMVHDB/;
 $seq = reverse $seq;
 return $seq;
}


=head3 cookies

Handle cookies. This method will get and set the value of the FIG cookie. Cookies are name/value pairs that are stored on the users computer. We then retrieve them using this method. The cookies are passed in as a reference to a hash, and the method returns a tuple of the cookie that can be passed to the browser and a reference to a hash with the data.

If you do not pass any arguments the whole cookie will be returned.

Use as follows:

($cookie, $data) = raelib->cookie($cgi, \%data); 

You do not need to pass in any data, in that case you will just get the cookie back

Underneath, I create a single cookie called FIG which stores all the information. The names and value pairs are stored using = to join name to value and ; to concatenate. This way we can create a single cookie with all the data. I am using the FIG::clean_attribute_key method to remove unwanted characters from the name/value pairs, so don't use them.

Note that for the moment I have put this routine here since it needs to maintain the state of the cookie (i.e. it needs to know what $self is). It should really be in HTML.pm but that is not, as far as I can tell, maintaining states?

=cut

sub cookie {
 my ($self, $cgi, $input)=@_;
 return unless ($cgi);
 $self->{'cookie'}=$cgi->cookie(-name=>"FIG") unless ($self->{'cookie'});
 
 # first, create a hash from the existing cookie data
 my $cookie;
 map {
  my ($kname, $kvalue)=split /\=/, $_;
  $cookie->{$kname}=$kvalue;
 } split /\;/, $self->{'cookie'};

 if ($input) 
 {
  # add the values that were passed in
  map {$cookie->{FIG->clean_attribute_key($_)}=$input->{$_}} keys %$input;
  # put everything back together and set the cookie
  my $newcookie=join ";", map {$_ . "=" . $cookie->{$_}} keys %$cookie;
  $self->{'cookie'}=$cgi->cookie(-name=>"FIG", -value=>$newcookie, -expires=>'+1y');
 }
 
 return ($self->{'cookie'}, $cookie);
}


=head3 is_number

returns 1 if the argument is a number, and 0 if not. This is taken directly from the perl cookbook.

=cut

sub is_number {
    my ($self, $no)=@_;
    return 1 if ($no =~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/); # Perl cookbook, page 44
    return 0;
}



=head3 commify

Put commas in numbers. I think this comes straight from the perl cookbook and is very useful for nice displays

=cut

sub commify {
    my($self,$n) = @_;
    my(@n) = ();
    my($i);

    for ($i = (length($n) - 3); ($i > 0); $i -= 3)
    {
        unshift(@n,",",substr($n,$i,3));
    }
    unshift(@n,substr($n,0,$i+3));
    return join("",@n);
}


=head3 tab2excel

This is experimental as of May, 2006.

There are a couple of perl modules that allow you to write to excel files, and so I am trying out the idea of taking our standard $tab table respresentation that is used in HTML.pm and making an excel file that people could download. It seems like that would be a great tool for them to have.

At the moment the excel modules are in my shared space on the CI machines, and so won't work in every seed installation. Therefore the $self->{'useexcel'} boolean is set at compile time if we successfully load the module.

The issues are:
    1. creating the excel file
    2. reading through @$tab and presenting the data
    3. Checking @$tab because each element can be a reference to an array with color or formatting information

Formatting

A separate set of formats must be created for each color and font combination since the formats are applied at the end of the processing of the file.


Usage:
    
    The recommended way of using this set of modules is to add the options excelfile=>"filename" to the options passed to &HTML::make_table. That should take care of EVERYTHING for you, so you should do that. You can call thinks separetly if you like, but I don't recommend it.

    Note that you can make multiple calls to the same excel file,a nd each one will get added as a new sheet.

    Note the usage is ALMOST the same as make_table, but not quite. First, options is a reference to a hash rather than the hash itself
    and second, the additional option "filename" that is the filename to be written;
    
    $url = $raelib->tab2excel($col_hdrs, $tab, $title, $options, "filename");

    The filename will be created in $FIG_Config::temp. The extension .xls will be added to the filename if it is not present.

Returns:
    A link to the file in the format 
        <p><a href="...">filename</a> [Download Excel file]</p>

Note that there are four separate methods:
    1. tab2excel is the method for a single call from HTML::make_table
        this will make an excel file, fill it, and return the link;
    2. make_excel_workbook is the method that instantiates a file
    3. make_excel_worksheet is the method that actually populates the file
        this loads all the data into the excel file, but if you know what you are doing you can call this many times, 
        each with a different spreadsheet
    4. close_excel_file
        this closes the file and writes it. This is called in the END block, so you do not have to explicitly call it here.

    tab2excel is a wrapper for all three so that the method in HTML::make_table is really easy.
    See subsys.cgi for a more complex involvement of this!


=cut

sub tab2excel {
    my($self, $col_hdrs, $tab, $title, $options, $filename)=@_;
    return "" unless ($self->{'useexcel'});
    #return "<p>Couldn't load Spreadsheet::WriteExcel</p>\n" unless ($self->{'useexcel'});
    $self->{'excel_file_link'} = $self->make_excel_workbook($filename, $options);
    $excelfilelink=$self->{'excel_file_link'};
    $self->make_excel_worksheet($col_hdrs, $tab, $title);
    return "" if ($options->{'no_excel_link'});
    return $self->{'excel_file_link'};
}
    

=head3 excel_file_link

Just returns the link to the file, if one has been created. If not, returns a non-breaking space (&nbsp;)

=cut

sub excel_file_link {
    my $self=shift;
    # I am not sure why, but this is not working. Perhaps because I am calling it from &HTML::make_table (i.e. not OO perl?)
    #print STDERR "SELF: $self LINK: ",$self->{'excel_file_link'}," or \n$excelfilelink\n";
    #return $self->{'excel_file_link'};
    return $excelfilelink;
}



=head3 make_excel_workbook

This is the method that actually makes individual workbook. You should call this once, with the name of the file that you want it to be known by. The options are to set borders and whatnot.

This will return the link to the workbook

=cut

sub make_excel_workbook {
    my($self, $filename, $options)=@_;
    return "" unless ($self->{'useexcel'});
    #return "<p>Couldn't load Spreadsheet::WriteExcel</p>\n" unless ($self->{'useexcel'});

    $filename =~ s/^.*\///; # remove any path information. We are going to only write to FIG_Config::temp
    unless ($filename =~ /\.xls$/) {$filename .=".xls"}
    
    # now generate the link to return
    my $link="<p><a href=\"".$fig->temp_url."/".$filename.'">'.$filename."</a> [Download table in Excel format].</p>\n";
    # do we already have this file -- if so, just return that info
    return  $link if ($self->{'excel_short_filename'} eq $filename); # don't do anything, just return the fact that we have the book made!

    
    $self->{'excel_short_filename'}=$filename;
    $self->{'excel_filename'}=$FIG_Config::temp."/$filename";


    # Each excel file consists of the file, and then of worksheets from within the file. These are the tabs at the bottom of the screen
    # that can be added with "Insert->new worksheet" from the menus.
    # Create a new workbook called simple.xls and add a worksheet

    # instantiate the workbook
    $self->{'excel_workbook'}=Spreadsheet::WriteExcel->new($self->{'excel_filename'});
    $excelfile=$self->{'excel_workbook'}; # this is for the close on END
    $self->{'excel_workbook'}->set_tempdir($FIG_Config::temp); # you don't have to do this, but it may speed things up and reduce memory load.

    # define the default formats
    my $border = defined $options->{border} ? $options->{border} : 0;
    $self->{'excel_format'}->{default}=$self->{'excel_workbook'}->add_format(border=>$border, size=>10);
    return $link;
}


=head3 make_excel_worksheet()

This is the method that makes the separate sheets in the file. You can add as many of these as you want.

=cut

sub make_excel_worksheet {
    my($self, $col_hdrs, $tab, $title)=@_;
    #return "<p>Couldn't load Spreadsheet::WriteExcel</p>\n" unless ($self->{'useexcel'});
    return "" unless ($self->{'useexcel'});

    unless (defined $self->{'excel_workbook'})
    {
        print STDERR "The workbook was not defined. Couldn't fill it in\n";
        return;
    }

    if (length($title) > 31) {$title=substr($title, 0, 31)}
    my $worksheet = $self->{'excel_workbook'}->add_worksheet($title);
    # The general syntax for output to an excel file is write($row, $column, $value, $format). Note that row and
    # column are zero indexed
    
    # write the column headers
    # define a new format that is bold
    $self->{'excel_format'}->{header} = $self->{'excel_workbook'}->add_format();
    $self->{'excel_format'}->{header}->copy($self->{'excel_format'}->{default});
    $self->{'excel_format'}->{header}->set_bold();
    
    for my $i (0 .. $#$col_hdrs)
    {
        my $cell;
        my ($useformat, $rowspan, $colspan);
        if (ref($col_hdrs->[$i]) eq "ARRAY") {($cell, $useformat, $rowspan, $colspan)=$self->parse_cell($col_hdrs->[$i])}
        else  {$cell=$col_hdrs->[$i]}
        $cell=$self->clean_excel_cell($cell);
        $worksheet->write(0, $i, $cell, $self->{'excel_format'}->{header});
    }

    # now loop through the table and write them out. Remember to break on array refs
    # we are going to have to build the table col by col so we get the breaks in the right place
    # for merged cells
    my $row_idx=1;
    my $maxrow=$#$tab;
    my $skip;
    while ($row_idx <= $maxrow+1)
    {
        my @row=@{$tab->[$row_idx-1]};
        my $col_idx=0;
        foreach my $cell (@row)
        {
            while ($skip->{$row_idx}->{$col_idx}) {$col_idx++}
            my $useformat=$self->{'excel_format'}->{default};

            # there is an approach to setting color using \@bgcolor. Oh well.
            if ( $cell =~ /^\@([^:]+)\:(.*)$/ )
            {
                $cell=[$2, $1];
            }
            
            my ($rowspan, $colspan);
            if (ref($cell) eq "ARRAY")
            {
                ($cell, $useformat, $rowspan, $colspan)=$self->parse_cell($cell);
            }
            
            $cell=$self->clean_excel_cell($cell);
            
            if ($rowspan > 1 || $colspan > 1) 
            {
                # handle merged cells separately
                my $row_idx_to=$row_idx+$rowspan-1;
                my $col_idx_to=$col_idx+$colspan-1;
                # we want to not put anything in the merged cells
                for (my $x=$row_idx; $x<=$row_idx_to; $x++) {$skip->{$x}->{$col_idx}=1}
                for (my $y=$col_idx; $y<=$col_idx_to; $y++) {$skip->{$row_idx}->{$y}=1}
               
                if (ref($cell) eq "ARRAY") {$worksheet->merge_range($row_idx, $col_idx, $row_idx_to, $col_idx_to, @$cell, $useformat)}
                else {$worksheet->merge_range($row_idx, $col_idx, $row_idx_to, $col_idx_to, $cell, $useformat)}
            }
            else 
            {
                # this is a botch, but in some circumstances we need to split the cell out. e.g. if it is a URL
                # in this case we have a reference to an array, and we'll use  a slight modification on the process
                if ((ref($cell) eq "ARRAY" && $cell->[0] eq " &nbsp; ") || $cell eq " &nbsp; ") {$worksheet->write_blank($row_idx, $col_idx, $useformat)}
                else
                {
                    if (ref($cell) eq "ARRAY") {$worksheet->write($row_idx, $col_idx, @$cell, $useformat)}
                    else {$worksheet->write($row_idx, $col_idx, $cell, $useformat)}
                }
            }
            
            # increment to the next column
            $col_idx++;
        }
        # new line, and start of line
        $row_idx++;
        $col_idx=0;
    }  
}




=head3 close_excel_file()

We must explicitly close the file before creating the link so that the file is written. This is also what returns the link

=cut

sub close_excel_file{
    my ($workbook)=@_;
    return unless (defined $workbook);
    # close the workbook. this writes the files
    return $workbook->close();    
}









=head3 parse_cell()

A method to take the cell from the table where there is some formatting information and figure out what we know. Return the data and the format.

Requires the cell and the current $format.

When applied to <td> the default formats that we'll deal with at the moment are
     align=
     background-color=
     color=
     bgcolor=

Colors are funky in excel because it only has a limited palette. We rename colors as needed, and then save those so that we can use them again. We're only allowed 55 colors in excel (numbered 8..63). Because its a little stupid to mess with black and white and so on, I ignore those, and also start renumbering at color number 20, giving us 43 different colors.

The reference to the hash excel_color has the custom excel colors stored in it for a few colors, and others are added to it.

=cut

sub parse_cell {
    my ($self, $arr)=@_;
    return ($arr, $self->{'excel_format'}->{default}) unless (ref($arr) eq "ARRAY");
    my ($cell, $tag)=@$arr;
    $tag =~ s/\'/"/g; # this just makes it easier to parse the things like align='center' and align="center" that are both valid

    # we are going to define a series of formats that we can apply, this will have  a key that is 
    # th.center.bgcolor.fgcolor. Then if we already have that, we can use it, if not, we'll define it
    
    my ($th, $center, $bgcolor, $fgcolor)=(0,0,0,0);
    
    if ($tag =~ /^th/) {$th=1} # it is a header cell so we should make it bold
    if ($tag =~ /align\=\"(.*?)\"/i) {$center=$1}
    
    # get rid of white tags because I don't care about them
    $tag =~ s/color\=.\#FFFFFF/ /ig;
    
    if ($tag =~ /background-color\=\"(.*?)\"/i || $tag =~ /bgcolor\=\"(.*?)\"/i)
    {
        my $color=$1;
        if ($color)
        {
            if (!defined $self->{'excel_color'}->{$color})
            {
# find out the last custom color used and increment it
                my $max=19; # we are not going to use a color less than 20
                    foreach my $k (keys %{$self->{'excel_color'}}) {($self->{'excel_color'}->{$k} > $max) ? ($max=$self->{'excel_color'}->{$k}) :1}
                $max++;
                $self->{'excel_color'}->{$color}=$self->{'excel_workbook'}->set_custom_color($max, $color);
            }
            $bgcolor=$self->{'excel_color'}->{$color};
        }
    }
    elsif ($tag =~ /color\=\"(.*?)\"/i || $tag =~ /color\=\'(.*?)\'/i)
    {
        my $color=$1;
        if (!defined $self->{'excel_color'}->{$color})
        {
            # find out the last custom color used and increment it
            my $max=19; # we are not going to use a color less than 20
            foreach my $k (keys %{$self->{'excel_color'}}) {($self->{'excel_color'}->{$k} > $max) ? ($max=$self->{'excel_color'}->{$k}) :1}
            $max++;
            $self->{'excel_color'}->{$color}=$self->{'excel_workbook'}->set_custom_color($max, $color);
        }
        $fgcolor=$self->{'excel_color'}->{$color};
    }
    
    # check and see if we span multiple rows or columns
    my ($rowspan, $colspan)=(1,1);
    if ($tag =~ /rowspan\=[\'\"]?(\d+)/) {$rowspan=$1} # these should match rowspan="4", rowspan='4', and rowspan=4
    if ($tag =~ /colspan\=[\'\"]?(\d+)/) {$colspan=$1} 
   
    my $formatid=$th.$center.$bgcolor.$fgcolor.$rowspan.$colspan;
    if (!defined $self->{'excel_format'}->{$formatid})
    {
        $self->{'excel_format'}->{$formatid}=$self->{'excel_workbook'}->add_format();
        if ($rowspan > 1) {$self->{'excel_format'}->{$formatid}->set_align("vcenter")}
        else
        {
            if ($th) {$self->{'excel_format'}->{$formatid}->copy($self->{'excel_format'}->{header})}
            else {$self->{'excel_format'}->{$formatid}->copy($self->{'excel_format'}->{default})}
        }
        $center && $self->{'excel_format'}->{$formatid}->set_align($center);
        $bgcolor && $self->{'excel_format'}->{$formatid}->set_bg_color($bgcolor);
        $fgcolor && $self->{'excel_format'}->{$formatid}->set_color($fgcolor);
    }
   
    return ($cell, $self->{'excel_format'}->{$formatid}, $rowspan, $colspan);
}

    
=head3 clean_excel_cell        
    
Process the cells to remove &nbsp; and also convert relative URLs to full URLs

=cut

sub clean_excel_cell {
    my ($self, $cell)=@_;
    if ($cell =~ /^\s*\&nbsp\;\s*$/) {$cell=undef} # ignore white space

    # some cells have something like this:
    # <a  onMouseover="javascript:if(!this.tooltip) this.tooltip=new Popup_Tooltip(this,'Role of BCAT','Branched-chain amino acid aminotransferase (EC 2.6.1.42)','','','','');this.tooltip.addHandler(); return false;" >BCAT</a>
    # we don't want those, but we do want the ones that have a real url hidden here.
    # so remove the mouseover part, and then see what is left
    if ($cell =~ s/onMouseover\=\".*?\"//)
    {
        if ($cell =~ s/\<a\s+>//i) {$cell =~ s/\<\/a>//i}
    }
        
    if ($cell =~ /\<a href=.(.*?).>(.*)<\/a>/)
    {
        # this is tricky because if the cell is a url then we need two separate things, the url and the link name
        my ($url, $link)=($1, $2);
        $url =~ s/^\.{1,2}\///; # remove notation of ./ and ../
        unless ($url =~ /^http/) {$url=$FIG_Config::cgi_url."/$url"}
        # this sucks as excel can only handle one link per cell, so we remove the other links. At the moment users will have to deal with that.
        $link =~ s/\<.*?\>//g;
        $cell=[$url, $link];
    }
    elsif ($cell =~ /<input type/)
    {
        if ($cell =~ /value='(.*?)'/) {$cell = $1}
        elsif ($cell =~ /value="(.*?)"/) {$cell = $1}
    }
    else
    {
        # this is all the html that I don't know what to do with, like <input type=...>
        $cell =~ s/\<.*?\>//g;
    }
    return $cell;
}
            
=head1 rand

Randomize an array using the fisher-yates shuffle described in the perl cookbook.

=cut

sub rand {
  my ($self, $array) = @_;
  my $i;
  for ($i = @$array; --$i; ) {
   my $j = int rand ($i+1);
   next if $i == $j;
   @$array[$i,$j] = @$array[$j,$i];
  }
  return $array;
}
    

1;

