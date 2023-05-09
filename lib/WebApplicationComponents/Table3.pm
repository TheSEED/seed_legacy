package WebApplicationComponents::Table3;

use strict;
use warnings;
use URI::Escape;

=head1 Table3 Module

This is a variation of [[Table1Pm]] used by [[DisplayRoleLiteratureCgi]].

=cut

1;

# initialize the table
sub new {
  my ($params) = @_;

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

  my $complex_filter    = $params->{complex_filter}    || 0;
  my $offset            = $params->{offset}            || 0;
  my $total             = scalar(@data)               || 0;
  $params->{total}      = $total;
  my $perpage           = $params->{perpage}           || -1;
  $params->{perpage}    = $perpage;
  my $id                = $params->{id}                || "table";
  $id =~ s/_//g;
  $params->{id}         = $id;
  my $img_path          = $params->{image_base}        || "./Html/";
  $params->{img_path}   = $img_path;
  my $show_perpage      = $params->{show_perpage}      || 0;
  my $show_topbrowse    = $params->{show_topbrowse}    || 0;
  my $show_bottombrowse = $params->{show_bottombrowse} || 0;
  my $group_cols        = $params->{group_cols}        || {};
  my $sortable          = $params->{sortable}          || 0;
  my $sortcols          = $params->{sortcols}          || { 'all' => 1 };
  my $control_menu      = $params->{control_menu};
  my $column_widths     = $params->{column_widths};
  my $collapsed_columns = $params->{collapsed_columns} || {};
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
    my $quoted_row;
    foreach my $cell (@$row) {
      $cell =~ s/\^/ /g;
      $cell =~ s/\~/ /g;
      push(@$quoted_row, $cell);
    }
    push(@$rows, join("^", @$quoted_row));
  }
  my $data_source = join("~", @$rows);

  $data_source =~ s/'/\@1/g;
  $data_source =~ s/"/\@2/g;

  # get the groupcol information
  my @group_cols_array;
  my $num_groupcols = 0;
  for (my $i=0; $i<scalar(@columns); $i++) {
    if (exists($group_cols->{$i})) {
      push(@group_cols_array, 1);
      $num_groupcols++;
    } else {
      push(@group_cols_array, 0);
    }
  }

  # insert hidden fields
  $table .= "\n<input type='hidden' id='table_data_" . $id . "' value='" . $data_source . "'>\n";
  $table .= "<input type='hidden' id='table_onclicks_" . $id . "' value='" . $onclicks . "'>\n";
  $table .= "<input type='hidden' id='table_titles_" . $id . "' value='" . $titles . "'>\n";
  $table .= "<input type='hidden' id='table_infos_" . $id . "' value='" . $infos . "'>\n";
  $table .= "<input type='hidden' id='table_menus_" . $id . "' value='" . $menus . "'>\n";
  $table .= "<input type='hidden' id='table_highlights_" . $id . "' value='" . $highlights . "'>\n";
  $table .= "<input type='hidden' id='table_filtereddata_" . $id . "' value=''>\n";
  $table .= "<input type='hidden' id='table_rows_" . $id . "' value='" .  $total . "'>\n";
  $table .= "<input type='hidden' id='table_cols_" . $id . "' value='" . scalar(@columns) . "'>\n";
  $table .= "<input type='hidden' id='table_start_" . $id . "' value='0'>\n";
  $table .= "<input type='hidden' id='table_numgroups_" . $id . "' value='" . $num_groupcols . "'>\n";
  $table .= "<input type='hidden' id='table_groups_" . $id . "' value='" . join(';', @group_cols_array) . "'>\n";
  $table .= "<input type='hidden' id='table_sortdirection_" . $id . "' value='up'>\n";

  # check for title
  if (defined($params->{title})) {
    $table .= "<p class='table_title'>" . $params->{title} . "</p>\n";
  }

  # check if table width was passed
  my $table_width = "";
  if (defined($params->{table_width})) {
    $table_width = "width: " . $params->{table_width} . "px;";
  }

  # check for control menu
  if ($control_menu) {

    # surrounding table
    $table .= "<table><tr><td>";

    # control tree columns
    $table .= "<table><tr><td>Visible Tree Columns</td></tr>";
    my @sorted_keys = sort(keys(%$group_cols));
    foreach my $key (@sorted_keys) {
      my $colname = $columns[$key];
      $table .= "<tr><td>$colname</td><td><input type='checkbox' name='" . $key  ."_vis' id='table_" . $id . "_" . $key  ."_vis' checked=checked></td></tr>";
    }
    $table .= "</table></td><td>";

    # control data columns
    $table .= "<div style='height: 250px; overflow: auto;'><table><tr><td>Visible Data Columns</td></tr>";
    for (my $i=0; $i<scalar(@columns); $i++) {
      unless ($group_cols->{$i}) {
	$table .= "<tr><td>" . $columns[$i] . "</td><td><input type='checkbox' name='" . $i  ."_vis' id='table_" . $id . "_" . $i  ."_vis'></td></tr>";
      }
    }
    $table .= "</table></div>";

    $table .= "</td></tr></table><input type='button' value='Apply' onclick='reload_table(\"" . $id . "\");'><input type='button' value='Show Data' onclick='switch_data_tree(\"" . $id . "\");' id='table_" . $id . "_switch_button'>";
  }

  # check for display options - select entries per page
  if ($show_perpage) {
    $table .= "<table class='table_table' style='$table_width'>\n<tr><td align=center><span class='table_perpage'>display&nbsp;<input type='text' id='table_perpage_" . $id . "' name='table_perpage_" . $id . "' size='3' value='" . $perpage . "' onkeypress='check_submit_filter(event, \"" . $id . "\")'>&nbsp;items per page</span></td></tr>\n";
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
    my $order_img = "<a href='javascript: table_sort(\"" . $id . "\", \"" . $i . "\", \"ASC\");' class='table_first_row' title='Click to sort'>";

    # create row collapse/expand button
    my $collapse_button = "";
    if ($group_cols->{$i - 1}) {
      if ($collapsed_columns->{$col}) {
	$collapse_button = "<img src='./Html/plus.gif' id='table_collapse_" . $id . "_" . ($i - 1) . "' onclick='expand_column(\"" . $id . "\", \"" . ($i - 1) . "\");'>";
      } else {
	$collapse_button = "<img src='./Html/minus.gif' id='table_collapse_" . $id . "_" . ($i - 1) . "' onclick='expand_column(\"" . $id . "\", \"" . ($i - 1) . "\");'>";
      }
    }

    # check for simple filter
    my $filter = "";
    if (defined($operands{$col})) {
      if ($complex_filter) {

	# check if there is a preselected value for this filter field
	my $preselected_operand = "";
	if (defined($operands{$col})) {
	  $preselected_operand = $operands{$col};
	}
	
	# check for filter comparison operator
	$filter = "<br/><select name='" . $id . "_" . $col . "_operator' id='table_" . $id . "_operator_" . $i . "' style='width: 40px;'>";
	
	foreach my $operator (@available_operators) {
	  my $preselected_operator = "";
	  
	  if (defined($preselected_operators{$col})) {
	    if ($preselected_operators{$col} eq $operator->[0]) {
	      $preselected_operator = " selected='selected'";
	    }
	  }
	  
	  $filter .= "<option value='" . $operator->[0] . "'" . $preselected_operator . ">" . $operator->[1] . "</option>";
	}
	$filter .= "</select><input type='text' name='" . $id . $col . "' class='filter_item' value='" . $preselected_operand . "'  id='table_" . $id . "_operand_" . $i . "' onkeypress='check_submit_filter(event, \"" . $id . "\")' style='width: 70%;'>";
      } else {
	my $operator = 'like';
	if (defined($preselected_operators{$col})) {
	  $operator = $preselected_operators{$col};
	}
	$filter = "<br/><input type=hidden name='" . $id . "_" . $col . "_operator' value='" . $operator . "' id='table_" . $id . "_operator_" . $i . "'><input type='text' name='" . $id . $col . "' class='filter_item' value='' size=5 id='table_" . $id . "_operand_" . $i . "' onkeypress='check_submit_filter(event, \"" . $id . "\")' style='width: 100%;' title='Enter Search Text'>";
      }
    }

    # check if colum header click should sort
   if (($sortable) && ($sortcols->{$col} || $sortcols->{'all'})) {
     $table .= "<td name='" . $name . "' class='table_first_row' style='" . $colwidths->[$i - 1] . "'>" . $collapse_button . $order_img . $col . "&nbsp;<img src='./Html/up-arrow.gif'><img src='./Html/down-arrow.gif'></a>" . $filter . "</td>";
    } else {
      $table .= "<td name='" . $name . "' class='table_first_row' style='" . $colwidths->[$i - 1] . "'>" . $collapse_button . $col . $filter . "</td>";
    }

    # increase column counter
    $i ++;
  }
  $table .= "</tr>";

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

  $browse .= "<tr><td><table class='table_browse'><tr><td align='left' width='20%'>" . $left . "</td><td align='center' width='60%'>displaying <span name='table_start_" . $id . "'>" . ($offset + 1) . "</span> - <span name='table_stop_" . $id . "'>" . $to . "</span> of <span name='table_total_" . $id . "'>" . $total . "</span></td><td align='right' width='20%'>" . $right . "</td></tr></table></td></tr>";
  
  return $browse;
}
