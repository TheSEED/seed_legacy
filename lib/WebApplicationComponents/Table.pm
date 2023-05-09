package WebApplicationComponents::Table;

use strict;
use warnings;
use URI::Escape;

=pod

#TITLE Table1Pm

  This is a Table Component from the days before the development of the [[WebApplication]] framework.

=cut

1;

sub new {
  my ($class, $params) = @_;

  # initialize variables
  my $table = "";

  # check for title
  if (defined($params->{title})) {
    $table .= "<p class='table_title'>" . $params->{title} . "</p>";
  }

  $table .= "<table class='table_table'>";

  # retrieve mandatory data from params
  my @data = @{$params->{data}};
  my @columns = @{$params->{columns}};

  # check for optional parameters in params
  my @available_operators = (
			     [ 'like', '&cong;' ],
			     [ 'unlike', '!&cong;' ],
			     [ 'equal', '=' ], [ 'unequal', '!=' ],
			     [ 'smaller', '<' ], [ 'greater', '>' ]
			    );
  if (defined($params->{available_operators})) {
    @available_operators = @{$params->{available_operators}};
  }

  my %preselected_operators = ();
  if (defined($params->{preselected_operators})) {
    %preselected_operators = %{$params->{preselected_operators}};
  }

  my %operands = ();
  if (defined($params->{operands})) {
    %operands = %{$params->{operands}};
  }
  unless (scalar(keys(%operands))) {
    if (defined($params->{show_filter})) {
      foreach my $column (@columns) {
	$operands{$column} = $available_operators[0];
      }
    }
  }

  my $offset            = $params->{offset} || 0;
  my $total             = $params->{total} || scalar(@data);
  $params->{total}      = $total;
  my $order_by          = $params->{order_by} || "";
  my $order             = $params->{order} || "ASC";
  $params->{order}      = $order;
  my $perpage           = $params->{perpage} || 20;
  $params->{perpage}    = $perpage;
  my $id                = $params->{id} || "table";
  $params->{id}         = $id;
  my $img_path          = $params->{image_base} || "../images/";
  $params->{img_path}   = $img_path;
  my $show_perpage      = $params->{show_perpage} || 0;
  my $show_topbrowse    = $params->{show_topbrowse} || 0;
  my $show_bottombrowse = $params->{show_bottombrowse} || 0;
  my $group_col         = $params->{group_col} || 0;
  my $enable_grouping   = $params->{enable_grouping} || 0;
  my $sortable          = $params->{sortable} || 0;

  # sanity check perpage value
  if (($perpage > $total) || ($perpage == -1)) {
    $perpage = $total;
    $params->{perpage} = $perpage;
  }
  
  # check for display options - select entries per page
  if ($show_perpage) {
    $table .= "<tr><td><div class='table_perpage'>display&nbsp;<input type='text' id='" . $id . "perpage' name='" . $id . "perpage' size='3' value='" . $perpage . "'>&nbsp;items per page</div></td></tr>";
  }
  
  # check for display options - display browsing element at the top
  if ($show_topbrowse) {
    $table .= get_browse($params);
  }
  
  # start data table
  $table .= "<tr><td><table class='table_table'>";
  
  # check for display options - display column filters
  if (scalar(keys(%operands)) > 0) {
    $table .= "<tr>";
    
    # check each value for an existing filter field
    foreach my $col (@columns) {
      if (exists($operands{$col})) {
	
	# check if there is a preselected value for this filter field
	my $preselected_operand = "";
	if (defined($operands{$col})) {
	  $preselected_operand = $operands{$col};
	}
	
	# check for filter comparison operator
	$table .= "<td><select name='" . $id . "_" . $col . "_operator'>";

	foreach my $operator (@available_operators) {
	  my $preselected_operator = "";

	  if (defined($preselected_operators{$col})) {
	    if ($preselected_operators{$col} eq $operator->[0]) {
	      $preselected_operator = " selected='selected'";
	    }
	  }

	  $table .= "<option value='" . $operator->[0] . "'" . $preselected_operator . ">" . $operator->[1] . "</option>";
	}
	$table .= "</select><input type='text' name='" . $id . $col . "' class='filter_item' value='" . $preselected_operand . "' onkeyup='check_edit_field(this);'></td>";
      } else {
	$table .= "<td></td>";
      }
    }
    
    $table .= "</tr>";
  }
  
  # write table header
  $table .= "<tr class='table_first_row'>";
  my $i = 1;

  # iterate through columns
  foreach my $col (@columns) {

    # count up column name
    my $name = $id . "_col_" . $i;

    # prepare html for sorting according to column
    my $order_img = "<a href='javascript: sort_table(\"" . $id . "\", \"" . $col . "\", \"ASC\");' class='table_first_row'>";
    if (($order_by) && ($col eq $order_by)) {
      if ($order eq "ASC") {
	$order_img = "<img src='" . $img_path . "da.png'><a href='javascript: sort_table(\"" . $id . "\", \"" . $col . "\", \"DESC\");' class='table_first_row'>";
      } else {
	$order_img = "<img src='" . $img_path . "ua.png'><a href='javascript: sort_table(\"" . $id . "\", \"" . $col . "\", \"ASC\");' class='table_first_row'>";
      }
    }

    # create config button
    my $conf_button = qq~<div style="background-color: white; border: 1px solid black; font-size: 7pt; padding: 1px; cursor: pointer; width: 13px; vertical-align: top; text-align: left;" class="hideme" onclick="change_group('$id\_col_$i');" id="$id\_col_$i" name="conf">+/-</div>~;

    # check if colum header click should sort
    if ($sortable) {
      $table .= "<td name='" . $name . "' class='visible_cell'><div class='table_first_row'>" . $conf_button . $order_img . $col . "</a></div></td>";
    } else {
      $table .= "<td name='" . $name . "' class='visible_cell'><div class='table_first_row'>" . $conf_button . $col . "</div></td>";
    }

    # increase column counter
    $i ++;
  }
  $table .= "</tr>";
  
  # iterate through data array
  my $odd = 1;
  my $isgrouped = 0;
  my $rowcount = 0;
  my $totalrows = scalar(@data);
  foreach my $row (@data) {

    # initialize variables
    my $prev = "";
    my $disp_group = "";
    
    # check for grouping if enabled
    if ($enable_grouping) {
      
      # check for last data set
      unless ($rowcount == $totalrows) {
	if (($row->[$group_col] eq $data[$rowcount + 1]->[$group_col]) && (!$isgrouped)) {
	  $prev = qq~<img src="~ . $img_path . qq~ungroup.png" onclick="check_grouping('~ . ($rowcount + 1) . qq~');" id="~ . $id . qq~group_img_~ . ($rowcount + 1) . qq~">~;
	  $isgrouped = $rowcount + 1;
	} else {
	  $disp_group = qq~ name="~ . $id . qq~group_~ . $isgrouped . qq~" class="hideme"~;
	  if ($isgrouped && ($row->[$group_col] ne $data[$rowcount + 1]->[$group_col])) {
	    $isgrouped = 0;
	  } elsif (!$isgrouped) {
	    $disp_group = "";
	  }
	}
      } elsif ($isgrouped) {
	$disp_group = qq~ name="~ . $id . qq~group_~ . $isgrouped . qq~" class="hideme"~;
      }
    }
    
    # start row
    $table .= "<tr" . $disp_group . ">";
    
    # initialize colcount
    my $colcount = 0;

    # print cells
    foreach my $cell (@$row) {

      # make sure the cell has a value
      unless (defined($cell)) {
	$cell = "&nbsp;";
      }

      # count up column name
      my $name = $id . "_col_" . ($colcount + 1);

      # make sure cell is defined
      unless (defined($cell)) { $cell = ""; }
      
      # check for style information
      $cell =~ /\|\^(.*)\^\|/;
      my $style = $1 || "";
      $cell =~ s/\|\^(.*)\^\|//;

      # start cell
      $table .= "<td name='" . $name . "' class='visible_cell' style='$style'>";
      if ($odd) {
	$table .= "<div class='table_odd_row'>";
      } else {
	$table .= "<div class='table_even_row'>";
      }
      if ($colcount == $group_col) {
	$table .= $prev . $cell . "</div></td>";
	$prev = "";
      } else {
	$table .= $cell . "</div></td>";
      }
      $colcount++;
    }
    $table .= "</tr>\n";
    if ($odd) {
      $odd = 0;
    } else {
      $odd = 1;
    }
    
    # increase rowcount
    $rowcount++;
  }
  
  # check if the last group is still open
  if ($isgrouped) {
    $table .= "</div>";
  }
  
  # end data table
  $table .= "</table></td></tr>";
  
  # check for display options - display browse element at the bottom
  if ($show_bottombrowse) {
    $table .= get_browse($params);  
  }
  
  # end surrounding table
  $table .= "</table>";

  return $table;
}

sub get_browse {
  my ($params) = @_;
  
  my $browse = "";
  my $left = "";
  my $right = "";
  my $offset = $params->{offset};
  my $id = $params->{id};
  my $perpage = $params->{perpage};
  my $total = $params->{total};

  if ($offset > 0) {
    $left .= "<a href='javascript: browse_table('" . $id . "', 'first');'>&laquo;first</a>&nbsp;&nbsp;<a href='javascript: browse_table('" . $id . "', 'prev');'>&laquo;prev</a>";
  }

  if (($offset + $perpage) < $total) {
    $right = "<a href='javascript: browse_table('" . $id . "', 'next');'>next&raquo;</a>&nbsp;&nbsp;<a href='javascript: browse_table('" . $id . "', 'last');'>last&raquo;</a>";
  }

  my $to = $offset + $perpage;
  if (($offset + $perpage) > $total) {
    $to = $total;
  }

  $browse .= "<tr><td><table class='table_browse'><tr><td align='left' width='20%'>" . $left . "</td><td align='center' width='60%'>displaying " . ($offset + 1) . " - " . $to . " of " . $total . "</td><td align='right' width='20%'>" . $right . "</td></tr></table></td></tr>";
  
  return $browse;
}
