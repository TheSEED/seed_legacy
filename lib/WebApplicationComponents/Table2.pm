package WebApplicationComponents::Table2;

use strict;
use warnings;
use URI::Escape;

1;



=head1 NAME

Table

=head1 DESCRIPTION

The Table Component implements an HTML/javascript table for displaying, filtering and browsing data.
It supports onClick events and popup menus for each cell. Data can also be grouped by a single column.
Like all WebApplicationComponents, configuration of columns to display is also supported.

=head1 ARGUMENTS

Arguments are passed as a single hash. All data must be passed as references (i.e. reference to an array
instead of an array). A table is instanciated via the I<new> method.

=head2 Mandatory Arguments

=over 3

=item B<data>

This must be an array of rows, each containing an array of cells. The data type of the cell contents is
detected for sorting issues. The first cell in a column will determine the data type. Three types of data
are differentiated:

Integers and Floats
Dates in the format mm/dd/yyyy
Strings

The cell data must not include quotation marks or linebreaks of any kind.

=item B<columns>

The columns are passed as an array of column headers, also no quotation marks or linebreaks are allowed.

=head2 Optional Arguments

=item B<id>

The identification of the table. Only neccessary if you have more than one table on a single page. Default is
'table'.

=item B<image_base>

The directory relative to the cgi directory where all images are stored. 'clear.gif' needs to be present in this
directory. Default is '../images'.

=item B<offset>

The array index of the first item in the list to be displayed. Default is 0.

=item B<perpage>

Number of items to be displayed on each page. Default is 20.

=item B<show_perpage>

Boolean to determine whether the user may change the number of items to be displayed on each
page. Default is false.

=item B<show_topbrowse>

Boolean to determine whether the browsing functions are displayed above the table. Default is
false.

=item B<show_bottombrowse>

Boolean to determine whether the browsing functions are displayed below the table. Default is
false.

=item B<enable_grouping>

Boolean to determine whether the grouping of a single column should be supported. Grouped
columns are collapsed if they contain consecutive identical values. They can be expanded
and collapsed by the user via a click on the symbol in the according cell. Default is false.

=item B<group_col>

Array index of the column to be the grouping column. Default is 0.

=item B<sortable>

Boolean to determine whether the user is allowed to sort the columns. Default is false.

=item B<show_filter>

Boolean to determine whether the user should be able to filter the columns. Default is false.

=item B<available_operators>

An array of operators available for filtering. Must be passed in the following format, which
is also the default:

 ( [ 'like', '&cong;' ],
  [ 'unlike', '!&cong;' ],
  [ 'equal', '=' ],
  [ 'unequal', '!=' ],
  [ 'less', '&lt;' ],
  [ 'more', '&gt;' ] )

Where the first entry is the operator and the second entry is the html to be displayed in the
select box.

=item B<preselected_operators>

A hash containing the column names as key and the operator to be pre-selected as a value. As
default, the first operator in the list is selected.

=item B<operands>

A hash containing the column names as key and the operand as values. If show_filter is true,
columns which are not a key of this hash will not receive a filter box.

=item B<onclicks>

If passed, this must be an array of rows, each containing an array of cells with the same
dimensions as the data array. The values should be urls that a click on the according cell
should link to.

=item B<popup_menu>

A hash containing the keys 'titles', 'infos' and 'menus'. Each of these have an array of arrays,
matching the dimensions of the data array, as a value. For usage of the popup menu, consult
the popup menu manual.

=back

=cut

# initialize the table
sub new {
  my ($class, $params) = @_;

  # initialize variables
  my $table = "";

  # retrieve mandatory data from params
  my @data;
  if (defined($params->{data})) {
    @data = @{$params->{data}};
  } else {
    return "No data passed to table creator!";
  }
  my @columns;
  if (defined($params->{columns})) {
    @columns = @{$params->{columns}};
  } else {
    return "No columns passed to table creator!";
  }

  # check for optional parameters in params
  my @available_operators = (
			     [ 'like', '&cong;' ],
			     [ 'unlike', '!&cong;' ],
			     [ 'equal', '=' ], [ 'unequal', '!=' ],
			     [ 'less', '&lt;' ], [ 'more', '&gt;' ]
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
	$operands{$column} = "";
      }
    }
  }

  my $offset            = $params->{offset}            || 0;
  my $total             = scalar(@data)               || 0;
  $params->{total}      = $total;
  my $perpage           = $params->{perpage}           || -1;
  $params->{perpage}    = $perpage;
  my $id                = $params->{id}                || "table";
  $params->{id}         = $id;
  my $img_path          = $params->{image_base}        || "./Html/";
  $params->{img_path}   = $img_path;
  my $show_perpage      = $params->{show_perpage}      || 0;
  my $show_topbrowse    = $params->{show_topbrowse}    || 0;
  my $show_bottombrowse = $params->{show_bottombrowse} || 0;
  my $group_col         = $params->{group_col}         || 0;
  my $enable_grouping   = $params->{enable_grouping}   || 0;
  my $sortable          = $params->{sortable}          || 0;
  my $column_widths     = $params->{column_widths};
  unless (defined($column_widths)) {
    foreach (@columns) {
      push(@$column_widths, -1);
    }
  }
  for (my $i=0; $i<scalar(@columns); $i++) {
    unless (defined($column_widths->[$i])) {
      $column_widths->[$i] = -1;
    }
  }

  # create an empty data array
  my $empty_array;
  my @good_data;
  foreach my $row (@data) {
    my $empty_row;
    my $good_row;
    foreach my $cell (@$row) {
      if (defined($cell)) {
	push(@$good_row, $cell);
      } else {
	push(@$good_row, "");
      }
      push(@$empty_row, "");
    }
    push(@$empty_array, $empty_row);
    push(@good_data, $good_row);
  }
  @data = @good_data;
  @good_data = undef;

  # create onclick event string
  my $onclicks = "";
  {
    my $onclicks_array = $params->{onclicks} || $empty_array;
    my $rows = [];
    foreach my $row (@$onclicks_array) {
      push(@$rows, join("^", @$row));
    }
    $onclicks = join("~", @$rows);
  }
  
  # create popup menu strings if requested
  my $titles = "";
  my $infos = "";
  my $menus = "";
  my $highlights = "";
  my ($titles_array, $infos_array, $menus_array, $highlights_array);
  {
    $titles_array     = $params->{popup_menu}->{titles} || $empty_array;
    $infos_array      = $params->{popup_menu}->{infos} || $empty_array;
    $menus_array      = $params->{popup_menu}->{menus} || $empty_array;
    $highlights_array = $params->{highlights} || $empty_array;
    
    my $rows = [];
    foreach my $row (@$titles_array) {
      push(@$rows, join("^", @$row));
    }
    $titles = join("~", @$rows);

    $rows = [];
    foreach my $row (@$infos_array) {
      push(@$rows, join("^", @$row));
    }
    $infos = join("~", @$rows);

    $rows = [];
    foreach my $row (@$menus_array) {
      push(@$rows, join("^", @$row));
    }
    $menus = join("~", @$rows);

    $rows = [];
    foreach my $row (@$highlights_array) {
      push(@$rows, join("^", @$row));
    }
    $highlights = join("~", @$rows);

    # check for unwanted symbols
    $infos =~ s/\n//g;
    $infos =~ s/'/&quot;/g;
    $infos =~ s/"/\\"/g;
    $menus =~ s/\n//g;
    $menus =~ s/'/&quot;/g;
    $menus =~ s/"/\\"/g;
  }

  # create stringified data
  my $rows = [];
  foreach my $row (@data) {
    push(@$rows, join("^", @$row));
  }
  my $data_source = join("~", @$rows);

  $data_source =~ s/'/\@1/g;
  $data_source =~ s/"/\@2/g;

  # insert hidden fields
  $table .= "\n<input type='hidden' value='" . $data_source . "' id='table_data_" . $id . "'>\n";
  $table .= "<input type='hidden' value='" . $onclicks . "' id='table_onclicks_" . $id . "'>\n";
  $table .= "<input type='hidden' value='" . $titles . "' id='table_titles_" . $id . "'>\n";
  $table .= "<input type='hidden' value='" . $infos . "' id='table_infos_" . $id . "'>\n";
  $table .= "<input type='hidden' value='" . $menus . "' id='table_menus_" . $id . "'>\n";
  $table .= "<input type='hidden' value='" . $highlights . "' id='table_highlights_" . $id . "'>\n";
  $table .= "<input type='hidden' value='' id='table_filtereddata_" . $id . "'>\n";
  $table .= "<input type='hidden' value='" .  $total . "' id='table_rows_" . $id . "'>\n";
  $table .= "<input type='hidden' value='" . scalar(@columns) . "' id='table_cols_" . $id . "'>\n";
  $table .= "<input type='hidden' value='0' id='table_start_" . $id . "'>\n";
  $table .= "<input type='hidden' value='up' id='table_sortdirection_" . $id . "'>\n";

  # check for title
  if (defined($params->{title})) {
    $table .= "<p class='table_title'>" . $params->{title} . "</p>\n";
  }

  # check if table width was passed
  my $table_width = "";
  if (defined($params->{table_width})) {
    $table_width = "width: " . $params->{table_width} . "px;";
  }

  # check for display options - select entries per page
  if ($show_perpage) {
    $table .= "<table class='table_table' style='$table_width'>\n<tr><td><span class='table_perpage'>display&nbsp;<input type='text' id='table_perpage_" . $id . "' name='table_perpage_" . $id . "' size='3' value='" . $perpage . "' onkeypress='check_submit_filter(event, \"" . $id . "\")'>&nbsp;items per page</span></td></tr>\n";
  } elsif ($perpage == -1) {
     $table .= "<input type='hidden' id='table_perpage_" . $id . "' name='table_perpage_" . $id . "' value='" . scalar(@data) . "' >\n<table class='table_table' style='$table_width'>\n";
  } else {
     $table .= "<input type='hidden' id='table_perpage_" . $id . "' name='table_perpage_" . $id . "' value='" . $perpage . "' >\n<table class='table_table' style='$table_width'>\n";
  }
  
  # check for display options - display browsing element at the top
  if ($show_topbrowse) {
    $table .= get_browse($params);
  }
  
  # start data table
  $table .= "<tr><td><table id='table_" . $id . "' class='table_table' style='$table_width'>";
  
  # check for display options - display column filters
#   if (scalar(keys(%operands)) > 0) {
#     $table .= "<tr>";
    
#     # check each value for an existing filter field
#     my $i = 0;
#     foreach my $col (@columns) {
#       if (exists($operands{$col})) {
	
# 	# check if there is a preselected value for this filter field
# 	my $preselected_operand = "";
# 	if (defined($operands{$col})) {
# 	  $preselected_operand = $operands{$col};
# 	}
	
# 	# check for filter comparison operator
# 	$table .= "<td><select name='" . $id . "_" . $col . "_operator' id='table_" . $id . "_operator_" . $i . "'>";

# 	foreach my $operator (@available_operators) {
# 	  my $preselected_operator = "";

# 	  if (defined($preselected_operators{$col})) {
# 	    if ($preselected_operators{$col} eq $operator->[0]) {
# 	      $preselected_operator = " selected='selected'";
# 	    }
# 	  }

# 	  $table .= "<option value='" . $operator->[0] . "'" . $preselected_operator . ">" . $operator->[1] . "</option>";
# 	}
# 	$table .= "</select><input type='text' name='" . $id . $col . "' class='filter_item' value='" . $preselected_operand . "'  id='table_" . $id . "_operand_" . $i . "' onkeypress='check_submit_filter(event, \"" . $id . "\")'></td>";
#       } else {
# 	$table .= "<td></td>";
#       }
#       $i++;
#     }
    
#     $table .= "</tr>";
#   }
  
  # write table header
  $table .= "<tr>";
  my $i = 1;

  # check column widths
  my $colwidths;

  # iterate through columns
  foreach my $col (@columns) {
    if ($column_widths->[$i - 1] ne -1) {
      push(@$colwidths, "width: " . $column_widths->[$i - 1] . "px;");
    } else {
      push(@$colwidths, "");
    }

    # count up column name
    my $name = $id . "_col_" . $i;

    # prepare html for sorting according to column
    my $order_img = "<a href='javascript: table_sort(\"" . $id . "\", \"" . $i . "\", \"ASC\");' class='table_first_row'>";

    # create config button
    my $conf_button = qq~<span style="background-color: white; border: 1px solid black; font-size: 7pt; padding: 1px; cursor: pointer; width: 13px; vertical-align: top; text-align: left;" class="hideme" onclick="change_group('$id\_col_$i');" id="$id\_col_$i" name="conf">+/-</span>~;

    # check for simple filter
    my $filter = "";
    if (defined($operands{$col})) {
      $filter = "<br/><input type=hidden name='" . $id . "_" . $col . "_operator' value='like' id='table_" . $id . "_operator_" . $i . "'><input type='text' name='" . $id . $col . "' class='filter_item' value=''  id='table_" . $id . "_operand_" . $i . "' onkeypress='check_submit_filter(event, \"" . $id . "\")'>";
    }

    # check if colum header click should sort
    if ($sortable) {
      $table .= "<td name='" . $name . "' class='table_first_row' style='" . $colwidths->[$i - 1] . "'>" . $conf_button . $order_img . $col . "</a>" . $filter . "</td>";
    } else {
      $table .= "<td name='" . $name . "' class='table_first_row' style='" . $colwidths->[$i - 1] . "'>" . $conf_button . $col . $filter . "</td>";
    }

    # increase column counter
    $i ++;
  }
  $table .= "</tr>";
  
#   # iterate through data array
#   my $odd = 1;
#   my $isgrouped = 0;
#   my $rowcount = 0;
#   my $totalrows = scalar(@data);
#   foreach my $row (@data) {
    
#     # initialize variables
#     my $prev = "";
#     my $disp_group = "";
    
#     # check for grouping if enabled
#     if ($enable_grouping) {
      
#       # check for last data set
#       unless ($rowcount == $totalrows) {
# 	if (($row->[$group_col] eq $data[$rowcount + 1]->[$group_col]) && (!$isgrouped)) {
# 	  $prev = qq~<img src="~ . $img_path . qq~ungroup.png" onclick="check_grouping('~ . ($rowcount + 1) . qq~');" id="~ . $id . qq~group_img_~ . ($rowcount + 1) . qq~">~;
# 	  $isgrouped = $rowcount + 1;
# 	} else {
# 	  $disp_group = qq~ name="~ . $id . qq~group_~ . $isgrouped . qq~" class="hideme"~;
# 	  if ($isgrouped && ($row->[$group_col] ne $data[$rowcount + 1]->[$group_col])) {
# 	    $isgrouped = 0;
# 	  } elsif (!$isgrouped) {
# 	    $disp_group = "";
# 	  }
# 	}
#       } elsif ($isgrouped) {
# 	$disp_group = qq~ name="~ . $id . qq~group_~ . $isgrouped . qq~" class="hideme"~;
#       }
#     }

#     # start row
#     $table .= "<tr id=\"" . $id . "_row_" . $rowcount . "\" name=\"" . $id . "_tablerow\">";
    
#     # initialize colcount
#     my $colcount = 0;
    
#     # print cells
#     foreach my $cell (@$row) {
      
#       # count up column name
#       my $name = $id . "_col_" . ($colcount + 1);
      
#       # make sure cell is defined
#       unless (defined($cell)) { $cell = ""; }
      
#       # check for style information
#       $cell =~ /\|\^(.*)\^\|/;
#       my $style = $1 || "";
#       $cell =~ s/\|\^(.*)\^\|//;
      
#       # start cell
#       if ($odd) {
# 	$table .= "<td name='" . $name . "' class='table_odd_row' style='$style'><span id='cell_" . $id . "_" . $colcount . "_" . $rowcount . "' name='table_cell'>";
#       } else {
# 	$table .= "<td name='" . $name . "' class='table_even_row' style='$style'><span id='cell_" . $id . "_" . $colcount . "_" . $rowcount . "' name='table_cell'>";
#       }
#       if ($colcount == $group_col) {
# 	$table .= $prev . $cell . "</span></td>";
# 	$prev = "";
#       } else {
# 	$table .= $cell . "</span></td>";
#       }
#       $colcount++;
#     }
#     $table .= "</tr>\n";
#     if ($odd) {
#       $odd = 0;
#     } else {
#       $odd = 1;
#     }
    
#     # increase rowcount
#     $rowcount++;
#   }
  
#   # check if the last group is still open
#   if ($isgrouped) {
#     $table .= "</span>";
#   }
  
  # end data table
  $table .= "</table></td></tr>";
  
  # check for display options - display browse element at the bottom
  if ($show_bottombrowse) {
    $table .= get_browse($params);  
  }
  
  # end surrounding table
  $table .= "</table>";

  # include image for table initialization
  $table .= "<img src='" . $img_path . "clear.gif' onload='initialize_table(\"" . $id . "\")'>";

  return $table;
}

# get the browsing html
sub get_browse {
  my ($params) = @_;
  
  my $browse  = "";
  my $left    = "";
  my $right   = "";
  my $offset  = $params->{offset} || 1;
  my $id      = $params->{id} || "table";
  my $perpage = $params->{perpage} || 0;
  my $total   = $params->{total} || 2;

  if ($offset > 0) {
    $left .= "<a href='javascript: table_first(\"" . $id . "\");' name='table_first_" . $id . "'>&laquo;first</a>&nbsp;&nbsp;<a href='javascript: table_prev(\"" . $id . "\");' name='table_prev_" . $id . "'>&laquo;prev</a>";
  }

  if (($offset + $perpage) < $total) {
    $right = "<a href='javascript: table_next(\"" . $id . "\");' name='table_next_" . $id . "'>next&raquo;</a>&nbsp;&nbsp;<a href='javascript: table_last(\"" . $id . "\");' name='table_last_" . $id . "'>last&raquo;</a>";
  }

  my $to = $offset + $perpage;
  if (($offset + $perpage) > $total) {
    $to = $total;
  }

  $browse .= "<tr><td><table class='table_browse'><tr><td align='left' width='20%'>" . $left . "</td><td align='center' width='60%'>displaying <input type='text' name='table_start_" . $id . "' class='disp' readonly=1 value='" . ($offset + 1) . "'> - <input type='text' name='table_stop_" . $id . "' class='disp' readonly=1 value='" . $to . "'> of <input type='text' name='table_total_" . $id . "' class='disp' readonly=1 value='" . $total . "'></td><td align='right' width='20%'>" . $right . "</td></tr></table></td></tr>";
  
  return $browse;
}
