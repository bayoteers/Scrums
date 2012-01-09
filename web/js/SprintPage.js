/**
  * The contents of this file are subject to the Mozilla Public
  * License Version 1.1 (the "License"); you may not use this file
  * except in compliance with the License. You may obtain a copy of
  * the License at http://www.mozilla.org/MPL/
  *
  * Software distributed under the License is distributed on an "AS
  * IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
  * implied. See the License for the specific language governing
  * rights and limitations under the License.
  *
  * The Original Code is the Scrums Bugzilla Extension.
  *
  * The Initial Developer of the Original Code is "Nokia Corporation"
  * Portions created by the Initial Developer are Copyright (C) 2011 the
  * Initial Developer. All Rights Reserved.
  *
  * Contributor(s):
  *   Eero Heino <eero.heino@nokia.com>
  */

function create_sprint_form_html(sprint, sprintid, edit)
{
    var template = $("#NewSprintTmpl").html();
    var sprint_id_str = "";
    if (sprintid != 0)
    {
        sprint_id_str = "<input type='hidden' name='sprintid' value='"+sprintid+"' />";
    }
    template = template.replace('<sprintid>', sprint_id_str);

    var buttons_str = "";
    if (edit) {
        buttons_str += '<input type="hidden" name="schema" value="editsprint" />';
        buttons_str += '<input type="submit" value="Delete" name="deletesprint" />';
        buttons_str += '&nbsp; | &nbsp';
        buttons_str += '<input type="button" value="Cancel" onclick="get_sprint();"/>&nbsp';
        buttons_str += '<input type="submit" name="editsprint" value="Save" onclick="return checkvalues();"/>';
    } else {
        buttons_str += '<input type="hidden" id="takebugs" name="takebugs" value="" />';
        buttons_str += '<input type="hidden" name="schema" value="newsprint" />';
        buttons_str += '<input type="submit" name="newsprint" value="Create" onclick="return checknewsprint();"/>';
    }
    template = template.replace('<buttonssection>', buttons_str);
    return template;
}

function checknewsprint()
{
    if(checkvalues()) {
        if(confirm('Do you want to move open bugs from previous sprint into new sprint?'))
        {
            $('#takebugs').attr({"value": "true"});
        }
        return true;
    } else {
        return false;
    }
}

function show_sprint(result)
{
    data = result.data;
    if(result.errormsg != "") {
        alert(result.errormsg);
        return;
    }
    data = result.data;

    var sprint = all_lists[0];
    sprint._status = data._status;
    sprint.description = data.description;
    sprint.start_date = data.start_date;
    sprint.end_date = data.end_date;

    sprint.estimatedcapacity = data.estimatedcapacity
    sprint.personcapacity = data.personcapacity
    sprint.pred_estimate = data.prediction;
    sprint.history = data.history;

    sprint_info_showed = true;
    $('#sprint_info').html(sprint.start_date+' &mdash; '+sprint.end_date);
    $('#sprint_button').html("<input type='button' value='Edit Sprint' onClick='edit_sprint();'/>");

    check_receive_status();
}

function edit_sprint()
{
    sprint = all_lists[0];
    $('#sprint').html(create_sprint_form_html(sprint, sprint.id, true /* edit */));
    $('#sprint_action').html('<h3>Edit Sprint</h3>');
    $("input[name=sprintname]").val(sprint.name.replace('Sprint ', ''));
    $("input[name=description]").val(sprint.description);
    $("input[name=start_date]").val(sprint.start_date);
    $("input[name=end_date]").val(sprint.end_date);
    $("input[name=submit]").val('Save');
    $('#personcapacity').html(sprint.personcapacity);
    $("input[name=estimatedcapacity]").val(sprint.estimatedcapacity);
    $('#estimate').html(sprint.pred_estimate);
    $('#history').html(sprint.history);
    // prepare Options Object
    var options = {
        success:   onCreateSprintDone,
        dataType: 'json'
    }
    $('#new_sprint_form').ajaxForm(options);
    var range_begin = "";
    var range_end = "";

    var today = new Date();
    $("#datepicker_min").datepicker({ maxDate: today, dateFormat: 'yy-mm-dd' });
    $("#datepicker_max").datepicker({ dateFormat: 'yy-mm-dd' });
}

function cancel()
{
    window.location = "page.cgi?id=scrums/teambugs.html&teamid=[% teamid %]";
}

function checkvalues()
{
    gettime();

    //var sprintname = window.document.forms['newsprint'].elements['sprintname'].value;
    var sprintname = $('input[name=sprintname]').val();

    if(sprintname == '') {
        alert("Sprint must have name.");
        return false;
    }

    if(sprintname.match(/^\S/) == null) {
        alert("Sprint name can not start with whitespace");
        return false;
    }

    if(range_begin == "") {
        alert("Sprint must have start date");
        return false;
    }

    return true;
}

function askconfirm()
{
    return confirm("Are you sure you want to delete sprint '[% sprintname %]'?");
}

function gettime()
{
    range_begin = $('#datepicker_min').val();
    range_end = $('#datepicker_max').val();
}


/**
 * Return a Date object representing the current time on the next business day
 * (e.g. on 3:41pm on a Friday, return 3:41pm on the following Monday).
 */
function getNextBusinessDay()
{
    var now = (new Date()).getTime();
    do {
        now += 86400 * 1000;
        var cur = new Date(now);
    } while(! (cur.getDay() >= 1 && cur.getDay() <= 5));
    return cur;
}


/**
 * Add some milliseconds to a Date object.
 */
function addDate(dt, ms)
{
    return new Date(dt.getTime() + ms);
}


function makeNewSprintForm()
{
    $('#sprint').html(create_sprint_form_html(sprint, 0 /* sprintid */, false /* edit */));
    $('#sprint_action').html('<h3>Create Sprint</h3>');

    $('#new_sprint_form').ajaxForm({
        success: onCreateSprintDone,
        dataType: 'json'
    });

    var range_begin = "";
    var range_end = "";

    var startDate = getNextBusinessDay();
    var days = SCRUMS_CONFIG.scrums_default_sprint_days;
    var endDate = addDate(startDate, days * 86400 * 1000);

    $("#datepicker_min").datepicker({
        maxDate: new Date(),
        dateFormat: 'yy-mm-dd'
    });
    $('#datepicker_min').datepicker('setDate', startDate);

    $("#datepicker_max").datepicker({
        defaultDate: endDate,
        dateFormat: 'yy-mm-dd'
    });
    $('#datepicker_max').datepicker('setDate', endDate);

    $('#history').html(sprint.history);
}

function get_sprint()
{
    if ($('#selected_sprint').val() == 'new_sprint') {
        makeNewSprintForm();
    } else {
        $.post('page.cgi?id=scrums/ajaxsprintbugs.html', {
            teamid: team_id,
            sprintid: $('#selected_sprint').val(),
        }, show_sprint, 'json');
    }
}

function onCreateSprintDone(result)
{
    data = result.data;
    if(result.errormsg != "") {
        alert(result.errormsg);
        return;
    }
    window.location.reload();
}
