package SeedComponents::PubMed;
use WebApplicationComponents qw(tabulator menu list table);
1;

use strict;
use FIG_Config;


my %month2num = (
	"jan" => '1',
	"feb" => '2',
	"mar" => '3',
	"apr" => '4',
	"may" => '5',
	"june" => '6',
	"jun" => '6',
	"july" => '7',
	"jul" => '7',
	"aug" => '8',
	"sep" => '9',
	"oct" => '10',
	"nov" => '11',
	"dec" => '12',
	);

my $entrez_base = "http://eutils.ncbi.nlm.nih.gov/entrez/";
my $journal_url = "$entrez_base"."eutils/esummary.fcgi?db=pubmed&id=";
my $url_format = "&retmode=xml";

sub new {
    my $package = shift;
    return bless({}, $package);
}

sub test_url_results {

    my $url = $_[0];
    
    # Searches Pubmed and Returns the number of results
    my $request=LWP::UserAgent->new();
    my $response=$request->get($url);
    my $results= $response->content;
    #die unless 
    
    if ($results ne "") {
	return $results;	
    }
    else {
	return;
    }
}


sub mysort {
 my ($peg,$pmid_a, $year_a, $month_a, $date_a, $title_a) = split(/\t/,$a);
 my ($peg,$pmid_b, $year_b, $month_b, $date_b, $title_b) = split(/\t/,$b); 		 	
 
 ($year_b) <=> ($year_a) || ($month2num{$month_a}) <=> ($month2num{$month_b}) 
 || ($date_a) <=> ($date_b);

 
}

sub get_journal_author {
    my $pmid = $_[0];
    
    my $url = "$journal_url"."$pmid"."$url_format";
    my $esearch_results = &test_url_results($url);
    my $author;
    if ($esearch_results) {

	$esearch_results =~ m/<Item Name=\"Author.* Type=\"String.*>(.*)<\/Item>/;
	$author .= "$1, ";
	$esearch_results =~ m/<Item Name=\"LastAuthor.*>(.*)<\/Item>/;
	$author .= $1;
	
    }
    return ($author);

}

sub process_and_sort_journals  {

    my $journal_in = $_[0];
    my @journals = @{$journal_in};
    my @entry;

    #Check to see that the urls do not fail. Get rid of the journals that do not have a result
    foreach (@journals) {
	my($pegs,$pmid)=split(/\t/,$_);

	my $url = "$journal_url"."$pmid"."$url_format";
	my $esearch_results = &test_url_results($url);
	if ($esearch_results) {
	    
	    my ($time, $year, $month, $date, $title);
	    $esearch_results =~ m/<*PubDate.*>(.*)<\/Item>/;
	    $time = $1;
	    ($year, $month, $date) = split(/ /,$time);	
	    $esearch_results =~ m/<*Title.*>(.*)<\/Item>/;
	    $title = $1;
	    
	    push(@entry, "$pegs\t$pmid\t$year\t$month\t$date\t$title");
	}
    }

    my @journals_out = (sort mysort @entry);
    
    return (@journals_out);
}


sub get_curated_journals_details {

    my $journal_in = $_[0];
    my @journals = @{$journal_in};
    my @entry;

    #Check to see that the urls do not fail. Get rid of the journals that do not have a result
    foreach (@journals) {
	my($who,$pmid)=split(/\t/,$_);

	my $url = "$journal_url"."$pmid"."$url_format";
	my $esearch_results = &test_url_results($url);
	if ($esearch_results) {
	    
	    my ($time, $year, $month, $date, $title);
	    $esearch_results =~ m/<*PubDate.*>(.*)<\/Item>/;
	    $time = $1;
	    ($year, $month, $date) = split(/ /,$time);	
	    $esearch_results =~ m/<*Title.*>(.*)<\/Item>/;
	    $title = $1;
	    
	    push(@entry, "$who\t$pmid\t$year\t$month\t$date\t$title");
	}
    }

    my @journals_out = (sort mysort @entry);
    
    return (@journals_out);
}

sub pmid_to_title {

    my $pmid_in = shift;
    
    my $url = "$journal_url"."$pmid_in"."$url_format";
    my $esearch_results = &test_url_results($url);
    my $esearch_title;
    
    
    if ($esearch_results) {
	   	    
	    $esearch_results =~ m/<*Title.*>(.*)<\/Item>/;
	    $esearch_title = $1;
	}

    return $esearch_title;


}

sub column_title {

   
    my $column_title = "<table cellspacing=10>";
    $column_title .= "<tr><td bgcolor=#D2E6F0>PEG</td>
                          <td bgcolor=#D2E6F0>PMID</td>
                          <td bgcolor=#D2E6F0>Publication: Year/Month/Day</td>	
                          <td bgcolor=#D2E6F0>Title</td></tr>";

    return $column_title;

}

sub journals_as_htmltable {

    my $journal_in = $_[0];
    my @journals = @{$journal_in};
    my $html_table;
    
    my @process_journals = &process_and_sort_journals (\@journals);
    foreach (@process_journals) {
	
	    my($pegs,$pmid,$yr,$month,$date, $title)=split(/\t/);
	    my $date="$yr $month $date";
	    
	    my $link = "http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?db=PubMed&term=$pmid";
	    
	    if ($pmid ne "") {
		$html_table .=  "<tr><td>$pegs</td><td><a href=$link target=_blank>$pmid</a></td><td>$date<td>$title</td>";
	    }
    }

    return $html_table;
}

sub journals_as_checkboxes {

    my $journal_in = $_[0];
    my @journals = @{$journal_in};
    my $html_table;
    
    my @process_journals = &process_and_sort_journals (\@journals);
    foreach (@process_journals) {
	
	    my($pegs,$pmid,$yr,$month,$date, $title)=split(/\t/);
	    my $date="$yr $month $date";
	    
	    my $link = "http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?db=PubMed&term=$pmid";
	    
	    if ($pmid ne "") {
		my $author = &get_journal_author($pmid);
		$html_table .=  "<tr><td><input type=radio name=$pmid value=ROLE_PUBMED_CURATED_NOTRELEVANT></td><td><input type=radio name=$pmid value=ROLE_PUBMED_CURATED_RELEVANT></td><td><a href=$link target=_blank>$pmid</a></td><td>$author</td><td>$date<td>$title</td>";
	    }
    }

    return $html_table;
}

sub curated_journals_as_checkboxes {

    my $journal_in = $_[0];
    my @journals = @{$journal_in};
    my $html_table;
    
    my @process_journals = &get_curated_journals_details(\@journals);
    foreach (@process_journals) {
	
	    my($who,$pmid,$yr,$month,$date, $title)=split(/\t/);
	    my $date="$yr $month $date";
	    
	    my $link = "http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?db=PubMed&term=$pmid";
	    
	    if ($pmid ne "") {
		my $author = &get_journal_author($pmid);
		$html_table .=  "<tr><td>$who</td><td><input type=radio name=$pmid value=ROLE_PUBMED_CURATED_NOTRELEVANT></td><td><input type=radio name=$pmid value=ROLE_PUBMED_CURATED_RELEVANT></td><td><a href=$link target=_blank>$pmid</a></td><td>$author</td><td>$date<td>$title</td>";
	    }
    }

    return $html_table;
}

sub get_citation {
    
    my ($self, $journal_in)=@_;

    #This subroutine gets the author, date, title, journal for a list of pubmed identifiers.  
    #May take in one or an array

    # This method returns a hash of hashes. The hash has the ID as the identifier, and then the hash for that ID has
    #	title
    #	author
    #	date
    #	journal

    my $publication_list;
    my $return;
    
    if (ref $journal_in eq 'ARRAY') {
	my @journals = @{$journal_in};
	foreach (@journals) {
	    $publication_list .= "$_,";   
	}
    }
    else {
	$publication_list = $journal_in;
    }
    
    my $url = "$journal_url"."$publication_list"."$url_format";
    
    if (my $esearch_results = &test_url_results($url)) {        

	my @tmp = split(/<DocSum>/, $esearch_results);
	open(O, ">$FIG_Config::temp/rob_sr.txt");
	print O $esearch_results;
	close O;

	foreach(@tmp) { 
	    my $out_info; my $id;
	    next if ($_ !~ m/<Id>/);

	    ( $_ =~ m/<Id>(.*)<\/Id>/ ) ? $id=$1 : 1;
	    ( $_ =~ m/<*Author.*>(.*)<\/Item>/ ) ? $out_info->{author}=$1 : 1;
	    ( $_ =~ m/<*PubDate.*>(.*)<\/Item>/ ) ? $out_info->{date}=$1 : 1;
	    ( $_ =~ m/<*Title.*>(.*)<\/Item>/ ) ? $out_info->{title}=$1 : 1;
	    ( $_ =~ m/<*Journal.*>(.*)<\/Item>/ ) ? $out_info->{journal}=$1 : 1;
	    $return->{$id} = $out_info;

	}
	
    }
    return $return;
}


sub get_author_date_title {
    #This subroutine gets the author, date, title for a list of pubmed identifiers.  
    #May take in one or an array

    my $journal_in = $_[0]; 
    my $publication_list;
    my $out_info;
    
    if (ref $journal_in eq 'ARRAY') {
	my @journals = @{$journal_in};
	foreach (@journals) {
	    $publication_list .= "$_,";   
	}
    }
    else {
	$publication_list = $journal_in;
    }
    
    my $url = "$journal_url"."$publication_list"."$url_format";
    
    if (my $esearch_results = &test_url_results($url)) {        

	my @tmp = split(/<DocSum>/, $esearch_results);
	foreach(@tmp) { 
	 
	    next if ($_ !~ m/<Id>/);

	    $_ =~ m/<Id>(.*)<\/Id>/;
	    $out_info .= "$1\;";
	    $_ =~ m/<*Author.*>(.*)<\/Item>/;
	    $out_info .= "$1,";
	    $_ =~ m/<*LastAuthor.*>(.*)<\/Item>/;
	    $out_info .= "$1\;";
	    $_ =~ m/<*PubDate.*>(.*)<\/Item>/;
	    $out_info .= "$1\;";
	    $_ =~ m/<*Title.*>(.*)<\/Item>/;
	    $out_info .= "$1\n";
	}
	
    }
    return $out_info;
}
1;
