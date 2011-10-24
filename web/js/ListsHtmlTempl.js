
/**
 * Functions that create one line into list must have equal parameters
 */
function create_item_line_html(bug, counter, show_columns)
{
    var str = '';
    if (bug[10]) {
        str += '<tr id=\'' + bug[0][0] + '\'  class="scrums_limited_area" bug_order_nr=\'' + counter + '\'>';
    }
    else {
        str += '<tr id=\'' + bug[0][0] + '\' bug_order_nr=\'' + counter + '\'>';
    }
    if ($.inArray('order', show_columns) > -1) { 
        str += '<td class=\'colF sortable\'> <span class=\'number\'>' + counter + '</span></td>';
    }
    if ($.inArray('bug_id', show_columns) > -1) {
	str += '<td class=\'colD sortable\'>' + bug[0][1] + '</td>';
    }
    if ($.inArray('points', show_columns) > -1) { 
	str += '<td class=\'colF sortable\'>' + bug[1] + '</td>';
    }
    if ($.inArray('status', show_columns) > -1) { 
	str += '<td class=\'colC sortable\'>' + bug[2] + '</td>';
    }
    if ($.inArray('assigned', show_columns) > -1) {
        str += '<td class=\'colA sortable\'>' + bug[3] + '</td>';
    }
    if ($.inArray('severity', show_columns) > -1) { 
        str += '<td class=\'colA sortable\'> ' + bug[7] + '</td>';
    }
    if ($.inArray('summary', show_columns) > -1) {  
	str += '<td title=\'' + bug[5] + '\' class=\'sortable\'> ' + bug[5] + '</td>';
    }
    if ($.inArray('creation_date', show_columns) > -1) {  
	str += '<td class=\'sortable\'>' + bug[6] + '</td>';
    }
    str += '</tr>';
    return str;
}

/**
 * Functions that create one line into list must have equal parameters
 */
function create_release_item_line(bug, counter, show_columns)
{
    var html = '<tr id="' + bug[0][0] + '" bug_order_nr="' + counter + '">';
    if ($.inArray('order', show_columns) > -1) {
        html += '<td class="colF"><span class="number">' + counter + '</span></td>';
    }
    if ($.inArray('creation_date', show_columns) > -1) {
        html += '<td class="sortable">' + bug[6] + '</td>';
    }
    html += '<td class="colD">' + bug[0][1] + '</td>';
    html += '<td class="colC">' + bug[1] + '</td>';
    html += '<td class="colD">' + bug[2] + '</td>';
    html += '<td class="colA">' + bug[3] + '</td>';
    if ($.inArray('severity', show_columns) > -1) {
        html += '<td class="colA sortable">' + bug[7] + '</td>';
    }
    html += '<td class="colB"><a href="page.cgi?id=scrums/createteam.html&teamid=' + bug[6] + '">' + bug[4] + '</a></td>';
    html += '<td><a href="page.cgi?id=scrums/sprintburndown.html&sprintid=' + bug[7] + '">' + bug[5] + '</a></td>';
    html += '</tr>';
    return html;
}


function create_list_html(list)
{
   var html = '<h3 id="' + list.h_id + '">'
   if(list.link_url)
   {
       html += '<a href="' + list.link_url + '">' + list.name + ' (<span id="items_' + list.id + '"></span>)</a>';
   }
   else
   {
       html += list.name;
   }
   html += '</h3>';
   html +=    '<div class="content" >';
   html +=      '<div class="scrollTableContainer" id="container">';
   html +=        '<table class="dataTable" id="table' + list.ul_id + '">';
   html +=          '<thead id="mythead">';
   html +=            '<tr>';
   if ($.inArray('order', list.show_columns) > -1) { 
       html += '<th class="sortable">#</th>';
   }
   if ($.inArray('bug_id', list.show_columns) > -1) {
       html += '<th class="sortable colF">' + field_descs.bug_id + '</th>';
   }
   if ($.inArray('points', list.show_columns) > -1) {
       html += '<th class="sortable colF">' + field_descs.remaining_time + '</th>';
   }
   if ($.inArray('status', list.show_columns) > -1) {
       html += '<th class="sortable colF">' + field_descs.bug_status + '</th>';
   }
   if ($.inArray('assigned', list.show_columns) > -1) {
       html += '<th class="sortable colF">' + field_descs.assigned_to + '</th>';
   }
   if ($.inArray('severity', list.show_columns) > -1) {
       html += '<th class="sortable colF">' + field_descs.bug_severity + '</th>';
   }
   if ($.inArray('summary', list.show_columns) > -1) {
       html += '<th class="sortable colF">' + field_descs.short_desc + '</th>';
   }
   if ($.inArray('creation_date', list.show_columns) > -1) {
       html += '<th class="sortable">' + field_descs.creation_ts + '</th>';
   }
   html +=            '</tr>';
   html +=          '</thead>';
   html +=        '<tbody id="' + list.ul_id + '" class="connectedSortable sortable">';
   html +=        '</tbody>';
   html +=      '</table>';
   html +=    '</div>';
   html +=  '</div>';
   return html;
}

function create_release_item_list_html(list) {
  var html = '<h3 id="' + list.h_id + '">' + list.name + '</h3>';
  html += '<div class="content">';
  html +=   '<p>';
  html +=     '<input type="button" value="Previous" OnClick=\'move_list_left("' + list.id + '");\'/>';
  html +=     '<input type="button" value="Next" OnClick=\'move_list_right("' + list.id + '");\'/>';
  html +=     'Show';
  html +=     '<select id="' + list.id + '" onchange=\'select_step("' + list.id + '");\'>';
  html +=       '<option>10</option>';
  html +=       '<option selected="selected">20</option>';
  html +=       '<option>50</option>';
  html +=       '<option>All</option>';
  html +=     '</select>';
  html +=     '(<span id="items_' + list.id + '"></span>)';
  html +=   '</p>';
  html +=   '<table class="dataTable">';
  html +=     '<thead>';
  html +=       '<tr>';
  html +=         '<th class="sortable">Priority</th>';
  html += 	  '<th class="sortable" class="colF">' + field_descs.bug_id + '</th>';
  html +=         '<th class="sortable" class="colF">' + field_descs.bug_status + '</th>';
  html +=         '<th class="sortable" class="colF">' + field_descs.bug_severity + '</th>';
  html +=         '<th class="sortable" class="colF">' + field_descs.short_desc + '</th>';
  html +=         '<th class="sortable" class="colF">Team</th>';
  html +=         '<th class="sortable" class="colF">Sprint</th>';
  html +=       '</tr>';
  html +=     '</thead>';
  html +=     '<tbody id="' + list.ul_id + '" class="connectedSortable sortable">';
  html +=     '</tbody>';
  html +=   '</table>';
  html += '</div>';
  return html;
}


