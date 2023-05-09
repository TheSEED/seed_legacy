package WebApplicationComponents::Menu;

1;

sub new {
  my ($class, $params) = @_;

  # retrieve params from param hash
  my @items = @{$params->{items}};
  my @links = @{$params->{links}};
  my $targets  = $params->{targets}  || {};
  my $selected = $params->{selected} || -1;
  my $id       = $params->{id}       || "menu";
  my $title    = $params->{title}    || "title";
     $class    = $params->{class}    || "";       #  Note reuse of $class

  # initialize menu string
  my $menu = "<div id='" . $id  ."' class='" . $class . "'><table class='div_box'>";

  # create menu title
  $menu .= qq~<tr><td id="~ . $id . qq~_add" class="hideme" onclick="add_element('~ . $id . qq~')">+</td><td id="~ . $id . qq~_clear" class="div_clear" onclick="change_element('~ . $id . qq~');"><li></td><td id="~ . $id . qq~_title" class="div_title_blue">~ . $title . qq~</td><td id="~ . $id . qq~_remove" class="hideme" onclick="remove_element('~ . $id . qq~')">x</td></tr><tr><td colspan=3 id="~ . $id . qq~_content" class="showme"><table style="width: 100%; background-color: white;">~;

  # fill in menu points
  my $curr = 0;
  foreach my $item (@items) {
    my $class_name = "menu_item";
    if ($curr == $selected) {
      $class_name = "menu_selected";
    }

    my $target = "";
    if (exists($targets->{$items[$curr]})) {
      $target = " target=_blank";
    }

    $menu .= "<tr><td><a href='" . $links[$curr] . "' class='" . $class_name . "' style='width: 190px;'" . $target . ">" . $items[$curr] . "</a></td></tr>";
    $curr++;
  }
  
  # close surrounding table and div
  $menu .= "</table></td></tr></table></div>";

  return $menu;
}
