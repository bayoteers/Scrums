
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
    } 
    else 
    {
        buttons_str += '<input type="hidden" name="schema" value="newsprint" />';
        buttons_str += '<input type="submit" name="newsprint" value="Create" onclick="return checkvalues();"/>';
    }
    template = template.replace('<buttonssection>', buttons_str);
    return template;
}

function show_sprint(result)
{
    data = result.data;
    if(result.errormsg != "")
    {
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
        success:   create_sprint,
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

        if(sprintname == '')
        {
          alert("Sprint must have name.");
          return false;
        }

        if(sprintname.match(/^\S/) == null)
        {
          alert("Sprint name can not start with whitespace");
          return false;
        }

        if(range_begin == "")
        {
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



function get_sprint()
{
    if ($('#selected_sprint').val() == 'new_sprint')
    {
        $('#sprint').html(create_sprint_form_html(sprint, 0 /* sprintid */, false /* edit */));
        $('#sprint_action').html('<h3>Create Sprint</h3>');
        
        var options = { 
            success:   create_sprint,
            dataType: 'json'
            } 
        $('#new_sprint_form').ajaxForm(options);

        var range_begin = "";
        var range_end = "";

        var today = new Date();
        $("#datepicker_min").datepicker({ maxDate: today, dateFormat: 'yy-mm-dd' });
        $("#datepicker_max").datepicker({ dateFormat: 'yy-mm-dd' });
        $('#history').html(sprint.history);
    } else
    {
            $.post('page.cgi?id=scrums/ajaxsprintbugs.html', {
            teamid: team_id,
            sprintid: $('#selected_sprint').val(),
        }, show_sprint, 'json');
   }
}

function create_sprint(result)
{
    data = result.data;
    if(result.errormsg != "")
    {
	alert(result.errormsg);
	return;
    }

    window.location.reload();
}

