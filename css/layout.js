/*

This script contains functionality for layouting web elements. The layout is kept
in a single string stored in an <input type=hidden> field. The layout can be
dynamically set by the user, or be determined by setting the value of this hidden
field. The style.css file must be included in the according web page for this
module to function. Also, a certain naming convention during the creation of the
web page must be used.

Currently supported functions are:

   - tables with configurable columns
   - menu boxes, which can be folded and unfolded, as well as being displayed or not
   - info boxes which can be clicked away
   - expandable sections

Under development:

   - tabbed views
   - browsable, filterable tables

*/

/* changes the visibility of an element and changes the layout information in the layout string */
function change_element (id, expand_title, collapse_title) {
    /* create regular expression to replace layout status of selected element */
    var re = new RegExp(id + ",element,1,\\d");
    var new_value;
    var new_label;

    /* switch visibility */
    var element = document.getElementById(id + '_content');
    if (element.className == "hideme") {
        element.className = "showme";
        new_value = "1";
        new_label = collapse_title;
    } else {
        element.className ="hideme";
        new_value = "0";
        new_label = "show";
        new_label = expand_title;
    }
    var layout_element = document.getElementById('layout');
    if (layout_element != undefined) {
        document.getElementById('layout').value =
            document.getElementById('layout').value.replace(re, id + ",element,1," + new_value);
    }
    var button_element = document.getElementById(id + '_link');
    button_element.value = new_label;
}

/* changes the visibility of an element */
function change_element2 (id) {
    
    /* switch visibility */
    var element = document.getElementById(id + '_content');
    var show_button = document.getElementById(id + '_show');
    var hide_button = document.getElementById(id + '_hide');
    if (element.className == "hideme") {
        element.className = "showme";
	show_button.className = "hideme";
	hide_button.className = "showme";
    } else {
        element.className ="hideme";
	show_button.className = "showme";
	hide_button.className = "hideme";
    }
}

/* collapses or expands a branch in a tree */
function treeswitch (id, number) {
    
    /* switch visibility */
    var element = document.getElementById(id + '_' + number + '_element');
    var image = document.getElementById(id + '_' + number + '_image');
    if (element.className == "hideme") {
        element.className = "showme";
	image.src = "./Html/minus.gif";
    } else {
        element.className ="hideme";
	image.src = "./Html/plus.gif";
    }
}

/* changes the visibility of a group of elements */
function change_group (name) {

    /* check for config mode */
    if (document.getElementById('config_mode').value == "1") {

        /* create regular expression to determine id of selected group */
        var re = new RegExp("([\\w\\d]+)_col");
        var regExpArray = re.exec(name);
        var id = regExpArray[1];
        re = new RegExp("_col_(\\d+)");
        regExpArray = re.exec(name);
        var column = regExpArray[1] - 1;

        /* create regular expression to replace layout status of selected element */
        re = new RegExp(id + ",group(,\\d)+;");
        regExpArray = re.exec(document.getElementById('layout').value);
        var element_string = regExpArray[0];
        re = new RegExp(id + ",group,");
        element_string = element_string.replace(re, '');
        var re = new RegExp("(\\d)", "g");
        var value_array = element_string.match(re);

        /* retrive element array */
        element_array = document.getElementsByName(name);
        
        /* change visibility */
        if (element_array[0].className == 'invisible_cell') {
            for (i=0; i<element_array.length; i++) {
                element_array[i].className = 'visible_cell';
                
            }
            value_array[column] = '1';
        } else {
            for (i=0; i<element_array.length; i++) {
                element_array[i].className = 'invisible_cell';
            }
            value_array[column] = '0';
        }

        /* change layout string */
        element_string = id + ",group," + value_array.join(',') + ";";
        re = new RegExp(id + ",group(,\\d)+;");
        document.getElementById('layout').value = document.getElementById('layout').value.replace(re, element_string);
    }
}

/* in config mode, adds element */
function add_element (id) {

    /* get element */
    var element_title = document.getElementById(id + '_title');
    var element_add = document.getElementById(id + '_add');
    var element_clear = document.getElementById(id + '_clear');
    var element_remove = document.getElementById(id + '_remove');

    /* set element to active */
    var rea = new RegExp(id + ",element,\\d,\\d,([a-z]*)");
    var element_data = rea.exec(document.getElementById('layout').value);
    element_title.className = 'div_title_' + element_data[1];
    element_add.className = 'hideme';
    element_clear.className = 'div_clear';
    element_remove.className = 'div_remove';

    /* change layout string */
    var reb = new RegExp(id + ",element,0");
    document.getElementById('layout').value = document.getElementById('layout').value.replace(reb, id + ",element,1");
}

/* in config mode, removes element */
function remove_element (id) {

    /* get element */
    var element_title = document.getElementById(id + '_title');
    var element_add = document.getElementById(id + '_add');
    var element_clear = document.getElementById(id + '_clear');
    var element_remove = document.getElementById(id + '_remove');

    /* set element to inactive */
    element_title.className = 'div_title_gray';
    element_add.className = 'div_add';
    element_clear.className = 'hideme';
    element_remove.className = 'hideme';

    /* change layout string */
    var re = new RegExp(id + ",element,1");
    document.getElementById('layout').value = document.getElementById('layout').value.replace(re, id + ",element,0");
}

/* starts and ends configuration mode */
function do_config () {

    /* aquire current layout string */
    var layout_string = document.getElementById('layout').value;
    
    /* get array of layout elements */
    var elements = layout_string.split(';');
    
    /* set all elements to config mode */
    for (i=0; i<elements.length; i++) {
        
        /* parse each element */
        var element_string = elements[i];
        var element_attributes = element_string.split(',');
        
        /* check for element type */
        if (element_attributes[1] == 'element') {
            
            /* aquire the element in question */
            var element = document.getElementById(element_attributes[0]);
            
            /* check if this element is currently present */
            if (element) {
                
                var element_title = document.getElementById(element_attributes[0] + '_title');
                var element_add = document.getElementById(element_attributes[0] + '_add');
                var element_clear = document.getElementById(element_attributes[0] + '_clear');
                var element_remove = document.getElementById(element_attributes[0] + '_remove');
                var element_content = document.getElementById(element_attributes[0] + '_content');
                
                /* set visibility of element */
                if (element_attributes[2] == '1') {
                    element.className = 'showme';
                    element_clear.className = 'div_clear';
                    element_remove.className = 'div_remove';
                } else {
                    element.className = 'showme';
                    element_add.className = 'div_add';
                    element_clear.className = 'hideme';
                    element_remove.className = 'hideme';
                    element_title.className = 'div_title_gray';
                }
                
                /* set visibility of sub element */
                if (element_attributes[3] == '1') {
                    element_content.className = 'showme';
                } else {
                    element_content.className = 'hideme';
                }
            }
            
            /* check for group type */
        } else if (element_attributes[1] == 'group') {
            
            /* is an element group */
            var column_array = element_attributes.slice(2);
            
            /* retrieve the value for each element of the group */
            for (h=0; h<column_array.length; h++) {
                var cells = document.getElementsByName(element_attributes[0] + '_col_' + (h + 1));
                
                /* check if this element is currently present */
                if (cells) {
                    
                    /* set visibility of each element in the group */
                    if (column_array[h] == 0) {
                        for (j=0; j<cells.length; j++) {
                            cells[j].className = 'invisible_cell';
                        }
                    } else {
                        for (j=0; j<cells.length; j++) {
                            cells[j].className = 'visible_cell';
                        }
                    }
                }
            }
        } else if (element_attributes[1] == 'section') {

             /* aquire the section in question */
            var section = document.getElementById(element_attributes[0]);
            var section_button = document.getElementById(element_attributes[0] + "_button");
            
            /* check if this section is currently present */
            if (section) {
                /* set visibility of element */
                if (element_attributes[2] == '1') {
                    section.className = 'showme';
                    section_button.value = 'less';
                } else {
                    section.className = 'hideme';
                    section_button.value = 'more';
                }
            }
        }
    }
}

/* performs layout for all elements */
function do_layout () {

    /* aquire current layout string */
    var layout_string = document.getElementById('layout').value;

    /* get array of layout elements */
    var elements = layout_string.split(';');
    for (i=0; i<elements.length; i++) {

        /* parse each element */
        var element_string = elements[i];
        var element_attributes = element_string.split(',');

        /* check for element type */
        if (element_attributes[1] == 'element') {

            /* is a single element */
            var element = document.getElementById(element_attributes[0]);
            if (element) {

                /* get element content and title */
                var element_content = document.getElementById(element_attributes[0] + '_content');
                var element_title = document.getElementById(element_attributes[0] + '_title');
                var element_remove = document.getElementById(element_attributes[0] + '_remove');
                
                /* set visibility of element */
                if (element_attributes[2] == '1') {
                    element.className = 'showme';
                    element_remove.className = 'hideme';
                    element_title.className = 'div_title_' + element_attributes[4];
                } else {
                    element.className = 'hideme';
                }
                
                /* set visibility of sub element */
                if (element_attributes[3] == '1') {
                    element_content.className = 'showme';
                } else {
                    element_content.className = 'hideme';
                }
            }

        /* check for group type */
        } else if (element_attributes[1] == 'group') {

            /* is an element group */
            var column_array = element_attributes.slice(2);

            /* retrieve the value for each element of the group */
            for (h=0; h<column_array.length; h++) {
                var cells = document.getElementsByName(element_attributes[0] + '_col_' + (h + 1));

                if (cells) {

                    /* set visibility of each element in the group */
                    if (column_array[h] == 0) {
                        for (j=0; j<cells.length; j++) {
                            cells[j].className = 'hideme';
                        }
                    } else {
                        for (j=0; j<cells.length; j++) {
                            cells[j].className = 'visible_cell';
                        }
                    }
                }
            }
        } else if (element_attributes[1] == 'section') {

             /* aquire the section in question */
            var section = document.getElementById(element_attributes[0]);
            var section_button = document.getElementById(element_attributes[0] + "_button");
            
            /* check if this section is currently present */
            if (section) {
                /* set visibility of element */
                if (element_attributes[2] == '1') {
                    section.className = 'showme';
                    section_button.value = 'less';
                } else {
                    section.className = 'hideme';
                    section_button.value = 'more';
                }
            }
        }
    }
}

/* show or hide extended information */
function extend (id) {
    element = document.getElementById(id);
    element_button = document.getElementById(id + "_button");

    /* check if section is in the layout string */
    var rea = new RegExp(id + ",section,\\d");
    var section = rea.exec(document.getElementById('layout').value);
    var reb = new RegExp(id + ",section,\\d");

    if (element.className == 'hideme') {
        element.className = 'showme';
        element_button.value = "less";

        if (section) {
            /* change layout string */
            document.getElementById('layout').value = document.getElementById('layout').value.replace(reb, id + ",section,1");
        }

    } else {
        element.className = "hideme";
        element_button.value = "more";

        if (section) {
            /* change layout string */
            document.getElementById('layout').value = document.getElementById('layout').value.replace(reb, id + ",section,0");
        }
    }
}

function toggle_menu () {
    var menutable = document.getElementById('menutable');
    if (menutable.style.display == 'none') {
        menutable.style.display = 'block';
    } else {
        menutable.style.display = 'none';
    }
}

/* highlight an item */
function highlight (id) {
    element = document.getElementById(id);
    element.className = 'highlight';
}

/* dehighlight */
function dehighlight (id) {
    element = document.getElementById(id);
    element.className = 'plain';    
}

/* test functions, document later!!! */
function check_sequence (id) {
    var sequence = document.getElementById('sequence').value;
    var tool = document.getElementById('blast_tool');
    var organism = document.getElementById(id).value;
    var re_dna = new RegExp("^[atgcnx\s\n\r\f]+$", "i");
    var re_protein = new RegExp("^[acdefghiklmnpqrstvwy\s\n\r\f]+$", "i");
    if (organism == "_choose_org") {
        alert("You must pick an organism");
    } else {
      if (sequence.match(re_dna)) {
	tool.selectedIndex = 1;
	document.forms.blast_form.submit();
      } else if (sequence.match(re_protein)) {
	tool.selectedIndex = 0;
	document.forms.blast_form.submit();
      } else {
	alert("Your query matches neither protein nor dna sequence.\nMake sure only valid letters are present.");
      }
    }
}

function submit_organism (id, action) {
    var element = document.getElementById(id);
    if (element.value == "_choose_org") {
        alert('Please pick an Organism from the list\nto proceed.');
    } else {
        document.getElementById('organism_action').value = action;
        document.forms.organism_form.submit();
    }
}

function go_configmode () {
    var mode = document.getElementById('config_mode');
    if (mode.value == 0) {

        /* enter configuration mode */
        mode.value = 1;

        /* make all configuration images visible */
        var conf_images = document.getElementsByName('conf');
        for (i=0; i<conf_images.length; i++) {
            conf_images[i].className = "showme";
        }

        document.getElementById('config').className = "showme";

        do_config();

    } else {

        /* leave configuration mode */
        mode.value = 0;

        document.getElementById('config').className = "hideme";

        if (confirm("save changes?")) {
            document.forms.configform.submit();
        } else {
            document.forms.login_form.submit();
        }
    }
}

function show_tip () {
    document.getElementById('ooo').className = 'showme';
    document.getElementById('xxx').className = 'hideme';
}

function hide_tip () {
    document.getElementById('xxx').className = 'showme';
    document.getElementById('ooo').className = 'hideme';
}

function showtab (collection, tab) {
  var alltabs = document.getElementsByName(collection);
  var activetab = document.getElementById(collection + '_' + tab);

  for (i=0; i<alltabs.length; i++) {
    alltabs[i].className = 'hideme';
  }
  
  activetab.className = 'showme';
}

/* ---------------------------------- */
/*          Table Functions           */
/* ---------------------------------- */
var SORT_COLUMN_INDEX;
var OPERAND;

var table_list = new Array();
var table_data = new Array();
var table_filtered_data = new Array();
var table_onclick_data = new Array();
var table_title_data = new Array();
var table_info_data = new Array();
var table_menu_data = new Array();
var table_highlight_data = new Array();

/* export the currently filtered table to a new window */
function export_table (id) {
    var data_index;
    for (i=0;i<table_list.length;i++) {
    	if (id == table_list[i]) {
    	    data_index = i;
    	}
    }
    var data_array = table_filtered_data[data_index];    

    var newwin = window.open();
    newwin.document.open();
    newwin.document.write("<pre>");
    for (i=0;i<data_array.length;i++) {
	newwin.document.write(data_array[i].join("\t") + "\n");
    }
    newwin.document.write("</pre>");
    newwin.document.close();
}

/* export the currently filtered table to a cgi form and submit it */
function export_table_form (table_id, field_id, form_id) {
    var data_index;
    for (i=0;i<table_list.length;i++) {
    	if (table_id == table_list[i]) {
    	    data_index = i;
    	}
    }
    var data_array = table_filtered_data[data_index];    

    var row_array = new Array();
    for (i=0;i<data_array.length;i++) {
	row_array[i] = data_array[i].join("^");
    }
    var data_string = row_array.join("~");
    document.getElementById(field_id).value = data_string;
    document.getElementById(form_id).submit();
}

/* execute the filter function if enter was pressed in a filter field */
function check_submit_filter (e, id) {
    if (e.keyCode == 13) {
   	table_filter(id);
    }
}

/* check the grouping / ungrouping in a table */
function check_grouping (column, group_id) {
    selimg = document.getElementById();
    seldiv = document.getElementsByName();
    if (seldiv[0].className == 'hideme') {
	selimg.src = 'group.png';
	for (i=0;i<seldiv.length;i++) {
	    seldiv[i].className = 'showme';
	}
    } else {
	selimg.src = 'ungroup.png';
	for (i=0;i<seldiv.length;i++) {
	    seldiv[i].className = 'hideme';
	}
    }
    return 1;
}

/* setup the table for initial display of data */
function initialize_table (id) {
    table_list[table_list.length] = id;
    
    if (document.getElementById("table_data_" + id)) {
	var data = document.getElementById("table_data_" + id).value;
	var re1 = new RegExp("@1", "g");
	var re2 = new RegExp("@2", "g");
	data = data.replace(re1, "'");
	data = data.replace(re2, "\"");

	var onclick_data = document.getElementById("table_onclicks_" + id).value;
	var title_data = document.getElementById("table_titles_" + id).value;
	var info_data = document.getElementById("table_infos_" + id).value;
	var menu_data = document.getElementById("table_menus_" + id).value;
	var highlight_data = document.getElementById("table_highlights_" + id).value;
	var index = table_data.length;
	table_data[index] = new Array();
	table_onclick_data[index] = new Array();
	table_title_data[index] = new Array();
	table_info_data[index] = new Array();
	table_menu_data[index] = new Array();
	table_highlight_data[index] = new Array();
	var rows = data.split(/~/);
	var onclick_rows = onclick_data.split(/~/);
	var title_rows = title_data.split(/~/);
	var info_rows = info_data.split(/~/);
	var menu_rows = menu_data.split(/~/);
	var highlight_rows = highlight_data.split(/~/);
	var numrows = rows.length;
	for (i=0; i<numrows; i++) {
	    var cells = rows[i].split(/\^/);
	    var onclick_cells = onclick_rows[i].split(/\^/);
	    var title_cells = title_rows[i].split(/\^/);
	    var info_cells = info_rows[i].split(/\^/);
	    var menu_cells = menu_rows[i].split(/\^/);
	    var highlight_cells = highlight_rows[i].split(/\^/);
	    var numcols = cells.length;
	    table_data[index][i] = new Array();
	    table_onclick_data[index][i] = new Array();
	    table_title_data[index][i] = new Array();
	    table_info_data[index][i] = new Array();
	    table_menu_data[index][i] = new Array();
	    table_highlight_data[index][i] = new Array();
	    for (h=0; h<numcols; h++) {
		table_data[index][i][h] = cells[h];
		table_onclick_data[index][i][h] = onclick_cells[h];
		table_title_data[index][i][h] = title_cells[h];
		table_info_data[index][i][h] = info_cells[h];
		table_menu_data[index][i][h] = menu_cells[h];
		table_highlight_data[index][i][h] = highlight_cells[h];
	    }
	    table_data[index][i][table_data[index][i].length] = i;
	}
	table_filter(id);
    }

    /* register table event handlers */
    var all_cells = document.getElementsByName('table_cell');
    for (i=0;i<all_cells.length;i++) {
	all_cells[i].onclick = table_onclick;
	all_cells[i].onmouseover = table_onmouseover;
	all_cells[i].onmouseout = table_onmouseout;
    }
}

/* handle the click events of table cells */
function table_onclick (e) {
    var cell = e.currentTarget.id;
    var m = cell.split(/_/);
    var id = m[1];
    var col = parseInt(m[2]);

    var data_index;
    for (i=0;i<table_list.length;i++) {
    	if (id == table_list[i]) {
    	    data_index = i;
    	}
    }

    var start = parseInt(document.getElementById('table_start_' + id).value);
    var row = table_filtered_data[data_index][parseInt(m[3]) + start][table_filtered_data[data_index][parseInt(m[3]) + start].length - 1];

    var loc = table_onclick_data[data_index][row][col];
    if (loc) {
    	window.top.location = loc;
    }
}

/* handle the mouseout events of table cells */
function table_onmouseout (e) {
    window.status='';
    //hidetip();
    return true;
}

/* handle the mouseover events of table cells */
function table_onmouseover (e) {
    var cell = e.currentTarget.id;
    var m = cell.split(/_/);
    var id = m[1];
    var col = parseInt(m[2]);

    var data_index;
    for (i=0;i<table_list.length;i++) {
      if (id == table_list[i]) {
	data_index = i;
      }
    }
    var start = parseInt(document.getElementById('table_start_' + id).value);
    var row = table_filtered_data[data_index][parseInt(m[3]) + start][table_filtered_data[data_index][parseInt(m[3]) + start].length - 1];
    
    var title = table_title_data[data_index][row][col];
    var info = table_info_data[data_index][row][col];
    var menu = table_menu_data[data_index][row][col];

    if(!e.currentTarget.tooltip) {
      e.currentTarget.tooltip = new Popup_Tooltip(e.currentTarget, title, info, menu);
      e.currentTarget.tooltip.addHandler();
      return true;
    }
}

/* filter the data of the table */
function table_filter (id) {
  var numcols      = parseInt(document.getElementById('table_cols_' + id).value);
  var rows_perpage = parseInt(document.getElementById('table_perpage_' + id).value);
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }
  
  var data_array = table_data[data_index];
  
  /* do the filtering step for each column that has a value entered in its filter box */
  for (z=0; z<numcols; z++) {
    var filter = document.getElementById('table_' + id + '_operand_' + (z + 1));
    SORT_COLUMN_INDEX = z;
    if (filter) {
      if (filter.value != '') {
	OPERAND = filter.value;
	operator = document.getElementById('table_' + id + '_operator_' + (z + 1)).value;
	if (operator == 'equal') {
	  data_array = array_filter(data_array, element_equal);
	} else if (operator == 'unequal') {
	  data_array = array_filter(data_array, element_unequal);
	} else if (operator == 'like') {
	  data_array = array_filter(data_array, element_like);
	} else if (operator == 'unlike') {
	  data_array = array_filter(data_array, element_unlike);
	} else if (operator == 'less') {
	  data_array = array_filter(data_array, element_less);
	} else if (operator == 'more') {
	  data_array = array_filter(data_array, element_more);
	}
      }
    }
  }
  
  /* put the array back into the string */
  newnumrows = data_array.length;
  document.getElementById('table_rows_' + id).value = newnumrows;
  table_filtered_data[data_index] = data_array;
  
  /* call a layout of the table */
  table_first(id);
}

/* sort the given table to the given col and order */
function table_sort (id, col) {
  /* get information from document */
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }
  var data_array = table_filtered_data[data_index];
  var numcols = parseInt(document.getElementById('table_cols_' + id).value) + 1;
  var numrows = parseInt(document.getElementById('table_rows_' + id).value);
  var dir = document.getElementById('table_sortdirection_' + id).value;
  col--;
  
  SORT_COLUMN_INDEX = col;
  
  /* determine data type */
  var sample_cell = data_array[0][col];
  var sortfn = sort_caseinsensitive_up;
  if (dir == "up") {
    document.getElementById('table_sortdirection_' + id).value = "down";
    if (sample_cell.match(/^\d\d[\/-]\d\d[\/-]\d\d\d\d$/)) sortfn = sort_date_up;
    if (sample_cell.match(/^\d\d[\/-]\d\d[\/-]\d\d$/)) sortfn = sort_date_up;
    if (sample_cell.match(/^[\d\.]+$/)) sortfn = sort_numeric_up;
  } else {
    document.getElementById('table_sortdirection_' + id).value = "up";
    sortfn = sort_caseinsensitive_down;
    if (sample_cell.match(/^\d\d[\/-]\d\d[\/-]\d\d\d\d$/)) sortfn = sort_date_down;
    if (sample_cell.match(/^\d\d[\/-]\d\d[\/-]\d\d$/)) sortfn = sort_date_down;
    if (sample_cell.match(/^[\d\.]+$/)) sortfn = sort_numeric_down;
  }
  
  /* execute sort */
  data_array.sort(sortfn);
  
  /* put the array back into the string */
  table_filtered_data[data_index] = data_array;
  
  /* call a layout of the table */
  table_first(id);
}

/* move to the next page of the selected table */
function table_next (id) {
    var start   = parseInt(document.getElementById('table_start_' + id).value);
    var perpage = parseInt(document.getElementById('table_perpage_' + id).value);
    var numrows = parseInt(document.getElementById('table_rows_' + id).value);

    start = start + perpage;
    var show_next = 1;
    var stop = start + perpage;
    if ((start + perpage) >= numrows) {
	start = numrows - perpage;
	stop = numrows;
	show_next = 0;
    }

    document.getElementById('table_start_' + id).value = start;

    fill_table(id, start, stop, 1, show_next);
}

/* move to the previous page of the selected table */
function table_prev (id) {
    var start   = parseInt(document.getElementById('table_start_' + id).value);
    var perpage = parseInt(document.getElementById('table_perpage_' + id).value);

    var stop = start;
    start = start - perpage;
    var show_prev = 1;
    if (start <= 0) {
	start = 0;
	stop = perpage;
	show_prev = 0;
    }

    document.getElementById('table_start_' + id).value = start;

    fill_table(id, start, stop, show_prev, 1);
}

/* move to the first page of the selected table */
function table_first (id) {
  var perpage = parseInt(document.getElementById('table_perpage_' + id).value);
  var numrows = parseInt(document.getElementById('table_rows_' + id).value);
  
  var start = 0;
  var stop = start + perpage;
  var show_next = 1;
  if (stop >= numrows) {
    stop = numrows;
    show_next = 0;
  }
  
  document.getElementById('table_start_' + id).value = start;
  
  fill_table(id, start, stop, 0, show_next);
}

/* move to the last page of the selected table */
function table_last (id) {
    var perpage = parseInt(document.getElementById('table_perpage_' + id).value);
    var numrows = parseInt(document.getElementById('table_rows_' + id).value);

    var stop = numrows;
    var start = numrows - perpage;
    var show_prev = 1;
    if (start <= 0) {
	start = 0;
	show_prev = 0;
    }

    document.getElementById('table_start_' + id).value = start;

    fill_table(id, start, stop, show_prev, 0);
}

/* get the filtered data from the document and fill the table accordingly */
function fill_table (id, start, stop, show_prev, show_next) {

  /* delete the old table */
  var table = document.getElementById('table_' + id).firstChild;
  numoldrows = table.childNodes.length - 1;
  for (i=0; i<numoldrows; i++) {
    table.removeChild(table.lastChild);
  }

  /* get data from the filtered data field */
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }
  var data_array = table_filtered_data[data_index];
  
  /* determine total number of rows */
  var numrows = data_array.length;
  document.getElementById('table_rows_' + id).value = numrows;
  
  /* iterate through the rows of the table */
  for (rownum=start; rownum<stop; rownum++) {

    /* get the cell data for this row */
    var cells = data_array[rownum];

    /* create the row element */
    var row = document.createElement("tr");
    row.name = id + "_tablerow";
    row.id = id + "_row_" + rownum;
    var celltype = "table_odd_row";
    if ((rownum % 2) == 1) {
      celltype = "table_even_row";
    }

    /* iterate through the cells of this row */
    for (colnum=0; colnum<(cells.length - 1); colnum++) {

      /* create the cell element */
      var td = document.createElement("td");
      var span = document.createElement("span");
      span.id = "cell_" + id + "_" + colnum + "_" + rownum;
      span.name = "table_cell";
      span.innerHTML = cells[colnum];
      span.onclick = table_onclick;
      span.onmouseout = table_onmouseout;
      span.onmouseover = table_onmouseover;
      if (table_onclick_data[data_index][rownum][colnum] != "") {
	span.style.cursor = 'pointer';
      }
      td.appendChild(span);
      td.className = celltype;
      td.id = id;
      row.appendChild(td);

      /* check for cell highlighting */
      if (table_highlight_data[data_index][rownum][colnum] == "1") {
	td.className = 'highlight';
      }
    }

    /* append the row to the tab;e */
    table.appendChild(row);
  }
  
  /* get all navigation elements */
  nexts = document.getElementsByName('table_next_' + id);
  lasts = document.getElementsByName('table_last_' + id);
  prevs = document.getElementsByName('table_prev_' + id);
  firsts = document.getElementsByName('table_first_' + id);
  
  /* set visibility of navigation elements */
  if (show_next) {
    for (i=0; i< nexts.length; i++) { nexts[i].style.display = 'inline'; }
    for (i=0; i< lasts.length; i++) { lasts[i].style.display = 'inline'; }
  } else {
    for (i=0; i< nexts.length; i++) { nexts[i].style.display = 'none'; }
    for (i=0; i< lasts.length; i++) { lasts[i].style.display = 'none'; }
  }
  if (show_prev) {
    for (i=0; i< prevs.length; i++) { prevs[i].style.display = 'inline'; }
    for (i=0; i< firsts.length; i++) { firsts[i].style.display = 'inline'; }
  } else {
    for (i=0; i< prevs.length; i++) { prevs[i].style.display = 'none'; }
    for (i=0; i< firsts.length; i++) { firsts[i].style.display = 'none'; }
  }
  
  /* set values of location displays */
  var starts = document.getElementsByName('table_start_' + id);
  for (i=0; i< starts.length; i++) {
    if (stop == 0) {
      starts[i].value = 0;
    } else {
      starts[i].value = start + 1;
    }
  }
  var stops = document.getElementsByName('table_stop_' + id);
  for (i=0; i< stops.length; i++) {
    stops[i].value = stop;
  }
  var totals = document.getElementsByName('table_total_' + id);
  for (i=0; i< totals.length; i++) {
    if (stop == 0) {
      totals[i].value = 0;
    } else {
      totals[i].value = numrows;
    }
  }
}

/* sort functions */
function sort_caseinsensitive_up (a, b) {
    aa = a[SORT_COLUMN_INDEX].toLowerCase();
    bb = b[SORT_COLUMN_INDEX].toLowerCase();
    if (aa==bb) return 0;
    if (aa<bb) return -1;
    return 1;
}

function sort_caseinsensitive_down (b, a) {
    aa = a[SORT_COLUMN_INDEX].toLowerCase();
    bb = b[SORT_COLUMN_INDEX].toLowerCase();
    if (aa==bb) return 0;
    if (aa<bb) return -1;
    return 1;
}

function sort_date_up (a, b) {
    aa = a[SORT_COLUMN_INDEX];
    bb = b[SORT_COLUMN_INDEX];
    if (aa.length == 10) {
        dt1 = aa.substr(6,4)+aa.substr(3,2)+aa.substr(0,2);
    } else {
        yr = aa.substr(6,2);
        if (parseInt(yr) < 50) { yr = '20'+yr; } else { yr = '19'+yr; }
        dt1 = yr+aa.substr(3,2)+aa.substr(0,2);
    }
    if (bb.length == 10) {
        dt2 = bb.substr(6,4)+bb.substr(3,2)+bb.substr(0,2);
    } else {
        yr = bb.substr(6,2);
        if (parseInt(yr) < 50) { yr = '20'+yr; } else { yr = '19'+yr; }
        dt2 = yr+bb.substr(3,2)+bb.substr(0,2);
    }
    if (dt1==dt2) return 0;
    if (dt1<dt2) return -1;
    return 1;
}

function sort_date_down (b, a) {
    aa = a[SORT_COLUMN_INDEX];
    bb = b[SORT_COLUMN_INDEX];
    if (aa.length == 10) {
        dt1 = aa.substr(6,4)+aa.substr(3,2)+aa.substr(0,2);
    } else {
        yr = aa.substr(6,2);
        if (parseInt(yr) < 50) { yr = '20'+yr; } else { yr = '19'+yr; }
        dt1 = yr+aa.substr(3,2)+aa.substr(0,2);
    }
    if (bb.length == 10) {
        dt2 = bb.substr(6,4)+bb.substr(3,2)+bb.substr(0,2);
    } else {
        yr = bb.substr(6,2);
        if (parseInt(yr) < 50) { yr = '20'+yr; } else { yr = '19'+yr; }
        dt2 = yr+bb.substr(3,2)+bb.substr(0,2);
    }
    if (dt1==dt2) return 0;
    if (dt1<dt2) return -1;
    return 1;
}

function sort_numeric_up (a, b) {
    aa = parseFloat(a[SORT_COLUMN_INDEX]);
    if (isNaN(aa)) aa = 0;
    bb = parseFloat(b[SORT_COLUMN_INDEX]); 
    if (isNaN(bb)) bb = 0;
    return aa-bb;
}

function sort_numeric_down (b, a) {
    aa = parseFloat(a[SORT_COLUMN_INDEX]);
    if (isNaN(aa)) aa = 0;
    bb = parseFloat(b[SORT_COLUMN_INDEX]); 
    if (isNaN(bb)) bb = 0;
    return aa-bb;
}

/* filter functions */
function array_filter (data, method) {
    var new_array = [];
    var orig_length = data.length;

    for (i=0; i<orig_length; i++) {
	if (method(data[i])) {
	    new_array[new_array.length] = data[i];
	}
    }

    return new_array;
}

function element_like(element) {
    re = new RegExp(OPERAND, "i");
    return (re.test(element[SORT_COLUMN_INDEX]));
}

function element_unlike(element) {
    re = new RegExp(OPERAND, "i");
    return (!re.test(element[SORT_COLUMN_INDEX]));
}

function element_equal(element) {
    return (element[SORT_COLUMN_INDEX] == OPERAND);
}

function element_unequal(element) {
    return (element[SORT_COLUMN_INDEX] != OPERAND);
}

function element_less(element) {
    if (element[SORT_COLUMN_INDEX].match(/^[\d\.]+$/)) {
	return (parseFloat(element[SORT_COLUMN_INDEX]) < parseFloat(OPERAND));
    }
    return (element[SORT_COLUMN_INDEX] < OPERAND);
}

function element_more(element) {
    if (element[SORT_COLUMN_INDEX].match(/^[\d\.]+$/)) {
	return (parseFloat(element[SORT_COLUMN_INDEX]) > parseFloat(OPERAND));
    }
    return (element[SORT_COLUMN_INDEX] > OPERAND);
}

/* -------------------------------------------------------------------------- */


/* show and hide subsystem diagram images */
/* (Subsystem.pm get_subsystem_diagrams) */
function show_image () {
  var select_box = document.getElementById('diagrams_select');
  var id = select_box.options[select_box.selectedIndex].value;
  var diagrams = document.getElementsByName('diagrams');
  for (i=0; i<diagrams.length; i++) {
    diagrams[i].className = 'hideme';
  }
  document.getElementById('diagram-'+id).className = 'showme';
}


/* highlight rows in the functional role table */
/* (Subsystem.pm get_subsystem_roles) */
function highlight_subset() {
  var select_box = document.getElementById('subset_select');
  var rows_string = select_box.options[select_box.selectedIndex].value;
  var rows = rows_string.split(/,/);

  i = 0;
  while (document.getElementById('roles_row_'+i)) {
    document.getElementById('roles_row_'+i).className = 'dehighlight';
    i++;
  }
  
  if (rows.length>0) {
    for(i=0; i<rows.length; i++) {
      document.getElementById('roles_row_'+rows[i]).className = 'highlight';
    }
  }
}

/* -------------------------------------------------------------------------- */
/* Filter Select */

function update_select (id) {
  var labels_string = document.getElementById("filter_select_labels_" + id).value;
  var values_string = document.getElementById("filter_select_values_" + id).value;
  var currval = document.getElementById("filter_select_currval_" + id);
  var re = new RegExp("{", "g");
  labels_string.replace(re, "'");
  values_string.replace(re, "'");
  var labels = labels_string.split(/~/);
  var values = values_string.split(/~/);

  var text = document.getElementById("filter_select_textbox_" + id).value;
  var select = document.getElementById("filter_select_" + id);
  select.options.length = 0;

  var escaped_text = "";
  for (i=0; i<text.length; i++) {
    switch (text.substr(i, 1))  {
    case '+':
      escaped_text  = escaped_text + "\\";
      break;
    case '(':
      escaped_text  = escaped_text + "\\";
      break;
    case ')':
      escaped_text  = escaped_text + "\\";
      break;
    case '\\':
      escaped_text  = escaped_text + "\\";
      break;
    case '^':
      escaped_text  = escaped_text + "\\";
      break;
    case '$':
      escaped_text  = escaped_text + "\\";
      break;
    case '{':
      escaped_text  = escaped_text + "\\";
      break;
    case '}':
      escaped_text  = escaped_text + "\\";
      break;
    case '[':
      escaped_text  = escaped_text + "\\";
      break;
    case ']':
      escaped_text  = escaped_text + "\\";
    }
    escaped_text  = escaped_text + text.substr(i, 1);
  }
  var re2 = new RegExp(escaped_text, "i");
  for (i=0; i<labels.length; i++) {
    if (labels[i].match(re2)) {
      select.options[select.options.length] = new Option(labels[i], values[i]);
    }
  }
  select.selectedIndex = 0;
  currval.value = select.options[select.selectedIndex].value;
}

function empty_select (id) {
  var textbox = document.getElementById("filter_select_textbox_" + id);
  if (textbox.value == 'Enter keyword to narrow search') {
    textbox.value = '';
  }
}

function update_select_text (id) {
  var textbox = document.getElementById("filter_select_textbox_" + id);
  var select = document.getElementById("filter_select_" + id);
  var currval = document.getElementById("filter_select_currval_" + id);
  currval.value = select.options[select.selectedIndex].value;
  textbox.value = select.options[select.selectedIndex].text;
}

/* -------------------------------------------------------------------------- */
/* Genome Browser */
/* -------------------------------------------------------------------------- */


function browse (command, id) {
  var browse_form = document.getElementById(id + '_form');
  var start_field = document.getElementById(id + '_start');
  var end_field = document.getElementById(id + '_end');
  var zoom_select = document.getElementById(id + '_zoom_select');

  var start = parseInt(start_field.value);
  var end = parseInt(end_field.value);
  var display_window = end - start;

  if (command == 'left_far') {
    start = start - display_window;
    end = end - display_window;
    if (start < 1) {
      start = 1;
    }
    if (end < (start + display_window)) {
      end = start + display_window;
    }
    
  } else if (command == 'left') {
    start = parseInt(start - (display_window / 2));
    end = parseInt(end - (display_window / 2));
    if (start < 1) {
      start = 1;
    }
    if (end < (start + display_window)) {
      end = start + display_window;
    }

  } else if (command == 'right') {
    start = parseInt(start + (display_window / 2));
    end = parseInt(end + (display_window / 2));

  } else if (command == 'right_far') {
    start = start + display_window;
    end = end + display_window;
    
  } else if (command == 'zoom_out') {
    if (zoom_select.selectedIndex > 0) {
      zoom_select.selectedIndex = zoom_select.selectedIndex - 1;
    }
    start = start + parseInt(display_window / 2);
    curr_zoom = parseInt(zoom_select.options[zoom_select.selectedIndex].value);
    start = start - parseInt(curr_zoom / 2);
    end = start + curr_zoom;

  } else if (command == 'zoom_in') {
    if (zoom_select.selectedIndex < zoom_select.options.length) {
      zoom_select.selectedIndex = zoom_select.selectedIndex + 1;
    }
    start = start + parseInt(display_window / 2);
    curr_zoom = parseInt(zoom_select.options[zoom_select.selectedIndex].value);
    start = start - parseInt(curr_zoom / 2);
    end = start + curr_zoom;

  } else if (command == 'zoom') {
    start = start + parseInt(display_window / 2);
    curr_zoom = parseInt(zoom_select.options[zoom_select.selectedIndex].value);
    start = start - parseInt(curr_zoom / 2);
    end = start + curr_zoom;

  }

  start_field.value = start;
  end_field.value = end;
  browse_form.submit();
}

function navigate (e) {
  var posx;
  
  if (!e) var e = window.event;
  if (e.pageX) 	{
    posx = e.pageX;
  }
  else if (e.clientX) 	{
    posx = e.clientX + document.body.scrollLeft + document.documentElement.scrollLeft;
  }
  posx = posx - this.offsetLeft - this.offsetParent.offsetLeft - this.offsetParent.offsetParent.offsetLeft;

  var id = this.id;
  var browse_form = document.getElementById(id + '_form');
  var start_field = document.getElementById(id + '_start');
  var end_field = document.getElementById(id + '_end');
  var total_field = document.getElementById(id + '_gsize');
  var start = parseInt(start_field.value);
  var end = parseInt(end_field.value);
  var window = end - start;
  
  var total = parseInt(total_field.value);
  var width = this.width;
  var factor = total / width;
  var middle = parseInt(posx * factor);
  start_field.value = middle - parseInt(window / 2);
  end_field.value = middle + parseInt(window / 2);
  
  browse_form.submit();
}

/* -------------------------------------------------------------------------- */
/* switch */
/* -------------------------------------------------------------------------- */

function switch_button (id, button) {
  var switch_a = document.getElementById(id + '_a_switch');
  var switch_b = document.getElementById(id + '_b_switch');
  var body_a = document.getElementById(id + '_a_body');
  var body_b = document.getElementById(id + '_b_body');
  
  if (button == 'a') {
    switch_a.className = 'switch_on';
    switch_b.className = 'switch_off';
    body_a.className = 'showme';
    body_b.className = 'hideme';
  } else {
    switch_b.className = 'switch_on';
    switch_a.className = 'switch_off';
    body_b.className = 'showme';
    body_a.className = 'hideme';
  }
}

/* -------------------------------------------------------------------------- */
/* Popup Tooltip */
/* -------------------------------------------------------------------------- */


var DIV_WIDTH=250;
var px;     // position suffix with "px" in some cases
var initialized = false;
var ns4 = false;
var ie4 = false;
var ie5 = false;
var kon = false;
var iemac = false;
var tooltip_name='popup_tooltip_div';

function Popup_Tooltip(object, tooltip_title, tooltip_text,
                       popup_menu, use_parent_pos, head_color,  body_color) {
    // the first time an object of this class is instantiated,
    // we have to setup some browser specific settings


    if(!initialized) {
         ns4 = (document.layers) ? true : false;
         ie4 = (document.all) ? true : false;
         ie5 = ((ie4) && ((navigator.userAgent.indexOf('MSIE 5') > 0) ||
                (navigator.userAgent.indexOf('MSIE 6') > 0))) ? true : false;
         kon = (navigator.userAgent.indexOf('konqueror') > 0) ? true : false;
         if(ns4||kon) {
             //setTimeout("window.onresize = function () {window.location.reload();};", 2000);
         }
         ns4 ? px="" : px="px";
		 iemac = ((ie4 || ie5) && (navigator.userAgent.indexOf('Mac') > 0)) ? true : false;

         initialized=true;
    }
    if (iemac) {
	    return;
    }
    this.tooltip_title = tooltip_title;
    this.tooltip_text = tooltip_text;
    if (head_color) {
     this.head_color = head_color;
    }
    else {
     this.head_color = "#333399";
    }

    if (body_color) {
     this.body_color = body_color;
    }
    else {
     this.body_color="#CCCCFF";
    }


    this.popup_menu = popup_menu;
    if (use_parent_pos) {
        this.popup_menu_x = object.offsetLeft;
        this.popup_menu_y = object.offsetTop + object.offsetHeight + 3;
    }
    else {
        this.popup_menu_x = -1;
        this.popup_menu_y = -1;
    }

    // create the div if necessary
    // the div may be shared between several instances
    // of this class

    this.div = getDiv(tooltip_name);
    if (!this.div) {
        // create a hidden div to contain the information
        this.div = document.createElement("div");
        this.div.id=tooltip_name;
        this.div.style.position="absolute";
        this.div.style.zIndex=0;
        this.div.style.top="0"+px;
        this.div.style.left="0"+px;
        this.div.style.visibility=ns4?"hide":"hidden";
        this.div.tooltip_visible=0;
        this.div.menu_visible=0
        document.body.appendChild(this.div);
    }
    // register methods
    this.showTip = showTip;
    this.hideTip = hideTip;
    this.fillTip = fillTip;
    this.showMenu = showMenu;
    this.hideMenu = hideMenu;
    this.fillMenu = fillMenu;
    this.addHandler = addHandler;
    this.delHandler = delHandler;
    this.mousemove = mousemove;
    this.showDiv = showDiv;

    // object state
    this.attached = object;
    object.tooltip = this;
}

function getDiv () {
    if (ie5 || ie4) {
		return document.all[tooltip_name];
	} else if (document.layers) {
        return document.layers[tooltip_name];
    }
    else if(document.all) {
        return document.all[tooltip_name];
    }
    return document.getElementById(tooltip_name);
}

function hideTip() {
    if (this.div.tooltip_visible) {
        this.div.innerHTML="";
        this.div.style.visibility=ns4?"hide":"hidden";
        this.div.tooltip_visible=0;
    }
}

function hideMenu() {
    if (this.div && this.div.menu_visible) {
        this.div.innerHTML="";
        this.div.style.visibility=ns4?"hide":"hidden";
        this.div.menu_visible=0;
    }
}

function fillTip() {
    this.hideTip();
    this.hideMenu();
    if (this.tooltip_title && this.tooltip_text) {
        this.div.innerHTML='<table width='+DIV_WIDTH+' border=0 cellpadding=2 cellspacing=0 bgcolor="'+this.head_color+'"><tr><td class="tiptd"><table width="100%" border=0 cellpadding=0 cellspacing=0><tr><th><span class="ptt"><b><font color="#FFFFFF">'+this.tooltip_title+'</font></b></span></th></tr></table><table width="100%" border=0 cellpadding=2 cellspacing=0 bgcolor="'+this.body_color+'"><tr><td><span class="pst"><font color="#000000">'+this.tooltip_text+'</font></span></td></tr></table></td></tr></table>';
        this.div.tooltip_visible=1;
    }
}


function fillMenu() {
    this.hideTip();
    this.hideMenu();
    if (this.popup_menu) {
        this.div.innerHTML='<table cellspacing="2" cellpadding="1" bgcolor="#000000"><tr bgcolor="#eeeeee"><td><div style="max-height:300px;min-width:100px;overflow:auto;">'+this.popup_menu+'</div></td></tr></table>';
        this.div.menu_visible=1;
    }
}

function showDiv(x,y) {
    winW=(window.innerWidth)? window.innerWidth+window.pageXOffset-16 :
        document.body.offsetWidth-20;
    winH=(window.innerHeight)?window.innerHeight+window.pageYOffset :
        document.body.offsetHeight;
    if (window.getComputedStyle) {
        current_style = window.getComputedStyle(this.div,null);
        div_width = parseInt(current_style.width);
        div_height = parseInt(current_style.height);
    }
    else {
        div_width = this.div.offsetWidth;
        div_height = this.div.offsetHeight;
    }
    this.div.style.left=(((x + div_width) > winW) ? winW - div_width : x) + px;
    this.div.style.top=(((y + div_height) > winH) ? winH - div_height: y) + px;
//	this.div.style.color = "#eeeeee";
    this.div.style.visibility=ns4?"show":"visible";
}

function showTip(e,y) {
    if (!this.div.menu_visible) {
        if (!this.div.tooltip_visible) {
            this.fillTip();
        }
        var x;
        if (typeof(e) == 'number') {
            x = e;
        }
        else {
            x=e.pageX?e.pageX:e.clientX?e.clientX:0;
            y=e.pageY?e.pageY:e.clientY?e.clientY:0;
        }
        x+=2; y+=2;
				this.showDiv(x,y);
        this.div.tooltip_visible=1;
    }
}

function showMenu(e) {
    if (this.div) {
        if (!this.div.menu_visible) {
            this.fillMenu();
        }
        var x;
        var y;

        // if the menu position was given as parameter
        // to the constructor, then use that position
        // or fall back to mouse position
        if (this.popup_menu_x != -1) {
            x = this.popup_menu_x;
            y = this.popup_menu_y;
        }
        else {
            x = e.pageX ? e.pageX : e.clientX ? e.clientX : 0;
            y = e.pageY ? e.pageY : e.clientY ? e.clientY : 0;
        }
	this.showDiv(x,y);
        this.div.menu_visible=1;
    }
}

// add the event handler to the parent object
function addHandler() {

    // the tooltip is managed by the mouseover and mouseout
    // events. mousemove is captured, too

	// we totally ignore Ie on mac
	if (iemac) {
	    return;
    }

    if(this.tooltip_text) {
	this.fillTip();
	this.attached.onmouseover = function (e) {
            this.tooltip.showTip(e);
            return false;
        };
	this.attached.onmousemove = function (e) {
            this.tooltip.mousemove(e);
            return false;
        };
    }
    if (this.popup_menu) {
        this.attached.onclick = function (e) {
                   this.tooltip.showMenu(e);

                   // reset event handlers
                   if (this.tooltip_text) {
                       this.onmousemove=null;
                       this.onmouseover=null;
                       this.onclick=null;
                   }

                   // there are two mouseout events,
                   // one when the mouse enters the inner region
                   // of our div, and one when the mouse leaves the
                   // div. we need to handle both of them
                   // since the div itself got no physical region on
                   // the screen, we need to catch event for its
                   // child elements
                   this.tooltip.div.moved_in=0;
                   this.tooltip.div.onmouseout=function (e) {
                       var div = getDiv(tooltip_name);
                       if (e.target.parentNode == div) {
                           if (div.moved_in) {
                               div.menu_visible = 0;
                               div.innerHTML="";
                               div.style.visibility=ns4?"hide":"hidden";
                           }
                           else {
                               div.moved_in=1;
                           }
                           return true;
                       };
                       return true;
                   };
                   this.tooltip.div.onclick=function() {
                       this.menu_visible = 0;
                       this.innerHTML="";
                       this.style.visibility=ns4?"hide":"hidden";
                       return true;
                   }
                   return false; // do not follow existing links if a menu was defined!

        };
    }
    this.attached.onmouseout = function () {
                                   this.tooltip.delHandler();
                                   return false;
                               };
}

function delHandler() {
    if (this.div.menu_visible) {
        return true;
    }

    // clean up
    if (this.popup_menu) {
        this.attached.onmousedown = null;
    }
    this.hideMenu();
    this.hideTip();
    this.attached.onmousemove = null;
    this.attached.onmouseout = null;
    // re-register the handler for mouse over
    this.attached.onmouseover = function (e) {
                                    this.tooltip.addHandler(e);
                                    return true;
                                };
    return false;
}

function mousemove(e){
    if (this.div.tooltip_visible) {
        if(e) {
            x=e.pageX?e.pageX:e.clientX?e.clientX:0;
            y=e.pageY?e.pageY:e.clientY?e.clientY:0;
        }
        else if(event) {
            x=event.clientX;
            y=event.clientY;
        }
        else {
            x=0; y=0;
        }
        if(document.documentElement) // Workaround for scroll offset of IE
        {
            x+=document.documentElement.scrollLeft;
            y+=document.documentElement.scrollTop;
        }
        this.showTip(x,y);
    }
}

function setValue(id , val) {
   var element = document.getElementById(id);
   element.value = val;
}
