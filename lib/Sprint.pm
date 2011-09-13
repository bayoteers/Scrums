# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Scrums Bugzilla Extension.
#
# The Initial Developer of the Original Code is "Nokia corporation"
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Visa Korhonen <visa.korhonen@symbio.com>

use strict;

package Bugzilla::Extension::Scrums::Sprint;

#use Bugzilla::Constants;
#use Bugzilla::Util;
use Bugzilla::Error;

use base qw(Bugzilla::Object);

##### Constants
#

###############################
####    Initialization     ####
###############################

use constant DB_TABLE   => 'scrums_sprints';
use constant LIST_ORDER => 'start_date';

use constant DB_COLUMNS => qw(
  id
  team_id
  name
  status
  description
  item_type
  start_date
  end_date
  estimated_capacity
  );

use constant REQUIRED_CREATE_FIELDS => qw(
  team_id
  name
  status
  );

use constant UPDATE_COLUMNS => qw(
  name
  status
  description
  start_date
  end_date
  estimated_capacity
  );

# Validators can not be used, because exceptions can not be thrown to ajax caller
use constant VALIDATORS => {};

###############################
####     Constructors     #####
###############################

###############################
####      Validators       ####
###############################

sub check_start_date {
    my ($self, $start_date) = @_;

    my $this_id   = $self->id();
    my $team_id   = $self->team_id();
    my $errordata = Bugzilla::Extension::Scrums::Sprint->_check_date($this_id, $team_id, $start_date);
    if ($errordata) {
        ThrowUserError('scrums_overlapping_sprint', $errordata);
    }
    return $start_date;
}

sub check_end_date {
    my ($self, $end_date) = @_;

    my $this_id   = $self->id();
    my $team_id   = $self->team_id();
    my $errordata = Bugzilla::Extension::Scrums::Sprint->_check_date($this_id, $team_id, $end_date);
    if ($errordata) {
        ThrowUserError('scrums_overlapping_sprint', $errordata);
    }
    return $end_date;
}

sub validate_span {
    my ($self, $this_id, $team_id, $span_start_date, $span_end_date) = @_;

    my $err = Bugzilla::Extension::Scrums::Sprint->_check_date($this_id, $team_id, $span_start_date);
    if ($err) {
        return "Sprint is overlapping another sprint '" . $err->{name} . "', start: " . $err->{start} . ", end: " . $err->{end};
    }
    $err = Bugzilla::Extension::Scrums::Sprint->_check_date($this_id, $team_id, $span_end_date);
    if ($err) {
        return "Sprint is overlapping another sprint '" . $err->{name} . "', start: " . $err->{start} . ", end: " . $err->{end};
    }
    $err = Bugzilla::Extension::Scrums::Sprint->_check_span($this_id, $team_id, $span_start_date, $span_end_date);
    if ($err) {
        return "Sprint is overlapping another sprint '" . $err->{name} . "', start: " . $err->{start} . ", end: " . $err->{end};
    }
    return undef;
}

sub _check_date {
    my ($self, $this_id, $team_id, $tested_date) = @_;

    if ($tested_date == undef) {
        return;
    }

    my ($sprint_id, $name, $start_date, $end_date);
    my $err = undef;
    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare(
        "select 
                        id, 
                        name, 
                        start_date, 
                        end_date        
                from 
                        scrums_sprints 
                where
                        item_type = 1 and 
                        (start_date is null or end_date is null) and 
                        team_id = ?"
                           );

    $sth->execute($team_id);
    while (($sprint_id, $name, $start_date, $end_date) = $sth->fetchrow_array) {
        if (!$this_id || $this_id != $sprint_id) {
            if (!$start_date) {
                $start_date = "null";
            }
            if (!$end_date) {
                $end_date = "null";
            }
            my %errordata;
            $errordata{'name'}  = $name;
            $errordata{'start'} = $start_date;
            $errordata{'end'}   = $end_date;
            $err                = \%errordata;
            return $err;
        }
    }

    $sth = $dbh->prepare(
        "select 
                        id, 
                        name, 
                        start_date, 
                        end_date 
                from 
                        scrums_sprints 
                where 
                        item_type = 1 and 
                        (start_date < ? or start_date is null) and 
                        (end_date > ? or end_date is null) and 
                        team_id = ?"
                        );
    $sth->execute($tested_date, $tested_date, $team_id);
    while (($sprint_id, $name, $start_date, $end_date) = $sth->fetchrow_array) {
        if (!$this_id || $this_id != $sprint_id) {
            if (!$start_date) {
                $start_date = "null";
            }
            if (!$end_date) {
                $end_date = "null";
            }
            my %errordata;
            $errordata{'name'}  = $name;
            $errordata{'start'} = $start_date;
            $errordata{'end'}   = $end_date;
            $err                = \%errordata;
            return $err;
        }
    }
}

sub _check_span {
    my ($self, $this_id, $team_id, $ref_start_date, $ref_end_date) = @_;

    my ($sprint_id, $name, $start_date, $end_date);
    my $err = undef;
    my $dbh = Bugzilla->dbh;

    if ($ref_end_date == undef) {

        my $sth = $dbh->prepare(
            "select 
                        id, 
                        name, 
                        start_date, 
                        end_date        
                from 
                        scrums_sprints 
                where
                        item_type = 1 and 
                        team_id = ? and
                        start_date > ?"
                               );
        $sth->execute($team_id, $ref_start_date);
        while (($sprint_id, $name, $start_date, $end_date) = $sth->fetchrow_array) {
            if (!$this_id || $this_id != $sprint_id) {
                my %errordata;
                $errordata{'name'}  = $name;
                $errordata{'start'} = $start_date;
                $errordata{'end'}   = $end_date;
                $err                = \%errordata;
                return $err;
            }
        }
    }
    else {
        my $sth = $dbh->prepare(
            "select 
                        id, 
                        name, 
                        start_date, 
                        end_date 
                from 
                        scrums_sprints 
                where 
                        item_type = 1 and 
                        (start_date > ? or start_date is null) and 
                        (end_date < ? or end_date is null) and 
                        team_id = ?"
                               );
        $sth->execute($ref_start_date, $ref_end_date, $team_id);
        while (($sprint_id, $name, $start_date, $end_date) = $sth->fetchrow_array) {
            if (!$this_id || $this_id != $sprint_id) {
                if (!$start_date) {
                    $start_date = "null";
                }
                if (!$end_date) {
                    $end_date = "null";
                }
                my %errordata;
                $errordata{'name'}  = $name;
                $errordata{'start'} = $start_date;
                $errordata{'end'}   = $end_date;
                $err                = \%errordata;
                return $err;
            }
        }
    }
}

###############################
####       Methods         ####
###############################

sub get_bugs {
    my $self = shift;
    if (!$self->{'my_bugs'}) {
        $self->set('my_bugs', $self->get_items());
    }
    return $self->{'my_bugs'};
}

sub get_work_done {
    my $self = shift;

    my $dbh = Bugzilla->dbh;
    my $sth = $dbh->prepare(
        'select
            sum(work_time) as w
        from 
            longdescs ld
        inner join
            scrums_sprint_bug_map sbm on
            sbm.bug_id = ld.bug_id
        where
            sprint_id = ? and 
            work_time > 0'
                           );
    $sth->execute($self->id);
    my ($work_done) = $sth->fetchrow_array();
    return $work_done;
}

sub get_capacity_summary {
    my $self = shift;

    my %capacity;
    my $capacity       = \%capacity;
    my $estimate       = $self->estimated_capacity();
    my $work_done      = $self->get_work_done();
    my $remaining_work = $self->calculate_remaining();
    my $total_work     = $work_done + $remaining_work;
    $capacity{sprint_capacity} = $estimate;
    $capacity{work_done}       = $work_done;
    $capacity{remaining_work}  = $remaining_work;
    $capacity{total_work}      = $total_work;
    $capacity{free_capacity}   = $estimate - $total_work;
    return $capacity;
}

sub calculate_remaining {
    my $self = shift;

    my $cum_rem     = 0;
    my $sprint_bugs = $self->get_bugs();
    for my $bug (@$sprint_bugs) {
        $cum_rem = $cum_rem + @$bug[1];
    }
    return $cum_rem;
}

sub get_member_capacity {
    my ($self, $member_id) = @_;

    my $dbh = Bugzilla->dbh;
    my $sth = $dbh->prepare(
        'select
            estimated_capacity
        from 
            scrums_sprint_estimate
        where
            sprintid = ? and 
            userid = ?'
                           );
    $sth->execute($self->id, $member_id);
    my $estimated_capacity = 0;
    my ($member_capacity) = $sth->fetchrow_array();
    if ($member_capacity) {
        $estimated_capacity = $member_capacity;
    }
    else {
        $estimated_capacity = "0.00";
    }
    return $estimated_capacity;
}

sub set_member_capacity {
    my ($self, $user_id, $capacity) = @_;

    my $sth = Bugzilla->dbh->prepare(
        'select
            estimated_capacity
        from 
            scrums_sprint_estimate
        where
            sprintid = ? and 
            userid = ?'
                                    );
    $sth->execute($self->id, $user_id);
    my ($old_capacity) = $sth->fetchrow_array();
    if ($old_capacity) {
        Bugzilla->dbh->do('UPDATE scrums_sprint_estimate set estimated_capacity = ? where sprintid = ? and userid = ?', undef, $capacity, $self->id, $user_id);
    }
    else {
        Bugzilla->dbh->do('INSERT INTO scrums_sprint_estimate (estimated_capacity, sprintid, userid) values (?, ?, ?)', undef, $capacity, $self->id, $user_id);
    }
}

sub get_member_workload {
    my ($self, $member_id) = @_;

    my $cum_member_workload = 0;
    my $sprint_bugs         = $self->get_bugs();
    for my $bug (@$sprint_bugs) {
        if (@$bug[7] == $member_id) {
            $cum_member_workload = $cum_member_workload + @$bug[1] + @$bug[8];
        }
    }
    return $cum_member_workload;
}

sub get_person_capacity {
    my ($self) = @_;

    my $dbh = Bugzilla->dbh;
    my $sth = $dbh->prepare(
        'select
            sum(estimated_capacity)
        from 
            scrums_sprint_estimate
        where
            sprintid = ?'
                           );
    $sth->execute($self->id);
    my $total_person_capacity = 0;
    my ($person_capacity) = $sth->fetchrow_array();
    if ($person_capacity) {
        $total_person_capacity = $person_capacity;
    }
    return $total_person_capacity;
}

sub get_previous_sprint {
    my ($self) = @_;

    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare('
        select 
	    id
        from 
	    scrums_sprints s1
        where 
	    not exists (select null 
        from 
	    scrums_sprints s2
        where 
	    s2.start_date > s1.start_date and
	    s2.start_date < ? and
	    s2.team_id = ? and
	    s2.item_type = 1)
        and 
	    s1.start_date < ? and
	    s1.team_id = ? and
	    s1.item_type = 1');
    $sth->execute($self->start_date, $self->team_id, $self->start_date, $self->team_id);
    my ($previous_sprint_id) = $sth->fetchrow_array();
    my $sprint = undef;
    if ($previous_sprint_id) {
        $sprint = Bugzilla::Extension::Scrums::Sprint->new($previous_sprint_id);
    }
    return $sprint;
}

sub get_predictive_estimate {
    my ($self) = @_;

    my %pred_estimate;
    my $pred_estimate = \%pred_estimate;
    my ($total_work_1, $tot_persons_1, $total_work_2, $tot_persons_2, $total_work_3, $tot_persons_3);
    my $prediction     = 0;
    my $work_done      = $self->get_work_done();
    my $remaining_work = $self->calculate_remaining();
    $total_work_1  = $work_done + $remaining_work;
    $tot_persons_1 = $self->get_person_capacity();

    my $sprint_m2 = $self->get_previous_sprint();
    my @previous_sprints;

    my (@sprint_hist1, @sprint_hist2, @sprint_hist3);
    push @sprint_hist1,     $self->name();
    push @sprint_hist1,     $total_work_1;
    push @sprint_hist1,     $tot_persons_1;
    push @previous_sprints, \@sprint_hist1;

    if (!$sprint_m2) {
        $prediction = $total_work_1;
    }
    else {
        $work_done      = $sprint_m2->get_work_done();
        $remaining_work = $sprint_m2->calculate_remaining();
        $total_work_2   = $work_done + $remaining_work;
        $tot_persons_2  = $sprint_m2->get_person_capacity();
        push @sprint_hist2,     $sprint_m2->name();
        push @sprint_hist2,     $total_work_2;
        push @sprint_hist2,     $tot_persons_2;
        push @previous_sprints, \@sprint_hist2;

        my $sprint_m3 = $sprint_m2->get_previous_sprint();
        if (!$sprint_m3) {
            $prediction = ($total_work_1 + $total_work_2) / 2;
        }
        else {
            $work_done      = $sprint_m3->get_work_done();
            $remaining_work = $sprint_m3->calculate_remaining();
            $total_work_3   = $work_done + $remaining_work;
            $tot_persons_3  = $sprint_m3->get_person_capacity();
            push @sprint_hist3,     $sprint_m3->name();
            push @sprint_hist3,     $total_work_3;
            push @sprint_hist3,     $tot_persons_3;
            push @previous_sprints, \@sprint_hist3;
            my $temp;

            if ($total_work_2 > $total_work_3) {
                $temp         = $total_work_3;
                $total_work_3 = $total_work_2;
                $total_work_2 = $temp;
            }
            if ($total_work_1 > $total_work_3) {
                $temp         = $total_work_3;
                $total_work_3 = $total_work_1;
                $total_work_1 = $temp;
            }
            if ($total_work_1 > $total_work_2) {
                $temp         = $total_work_2;
                $total_work_2 = $total_work_1;
                $total_work_1 = $temp;
            }
            $prediction = $total_work_2;
        }
    }
    $pred_estimate->{'prediction'} = $prediction;
    $pred_estimate->{'history'}    = \@previous_sprints;

    return \%pred_estimate;
}

sub get_items {
    my $self = shift;
    my $dbh  = Bugzilla->dbh;
    my ($sprint_bugs) = $dbh->selectall_arrayref(
        'select
        b.bug_id,
        b.remaining_time,
        b.bug_status,
        p.realname,
        left(b.short_desc, 40),
        b.short_desc,
        b.creation_ts,
        b.bug_severity,
        bo.team,
        b.assigned_to,
        sum(work_time) as work_done,
        sum(work_time)+b.remaining_time as total_work
    from
	scrums_sprint_bug_map sbm
	inner join bugs b on sbm.bug_id = b.bug_id
        inner join profiles p on p.userid = b.assigned_to
        inner join longdescs l on l.bug_id = b.bug_id
	left join scrums_bug_order bo on sbm.bug_id = bo.bug_id
    where
	sbm.sprint_id = ?
    group by
        b.bug_id,
        b.remaining_time,
        b.bug_status,
        p.realname,
        left(b.short_desc, 40),
        b.short_desc,
        bo.team,
        b.assigned_to
    order by
	bo.team', undef, $self->id
    );
    return $sprint_bugs;
}

sub get_item_array {
    my $self = shift;
    my $dbh  = Bugzilla->dbh;
    my ($sprint_items) = $dbh->selectall_arrayref(
        'select
        bug_id
    from
	scrums_sprint_bug_map
    where
	sprint_id = ?', undef, $self->id
    );
    my @array;
    for my $row (@{$sprint_items}) {
        push(@array, @{$row}[0]);
    }
    return \@array;
}

sub is_item_in_sprint {
    my $self = shift;
    my ($bug_id) = @_;

    my $item_array = $self->get_item_array();
    my @matches = grep { $_ eq $bug_id } @{$item_array};
    return ((scalar @matches) > 0);
}

sub set_name               { $_[0]->set('name',               $_[1]); }
sub set_status             { $_[0]->set('status',             $_[1]); }
sub set_description        { $_[0]->set('description',        $_[1]); }
sub set_start_date         { $_[0]->set('start_date',         $_[1]); }
sub set_end_date           { $_[0]->set('end_date',           $_[1]); }
sub set_estimated_capacity { $_[0]->set('estimated_capacity', $_[1]); }

sub add_item_list_history {
    my $self = shift;
    my ($dbh, $added_bug_id, $to_team_order, $to_sprint_id, $from_team_order, $from_sprint_id, $user_id) = @_;

    my ($localtime_sec, $localtime_min, $localtime_hour, $localtime_day, $localtime_month, $localtime_year) = localtime();
    my $now =
      sprintf("%04d-%02d-%02d %02d:%02d:%02d", 1900 + $localtime_year, 1 + $localtime_month, $localtime_day, $localtime_hour, $localtime_min, $localtime_sec);

    $dbh->do(
'INSERT INTO scrums_item_list_history (bug_id, from_sprint_id, to_sprint_id, from_team_order, to_team_order, userid, update_ts) values (?, ?, ?, ?, ?, ?, ?)',
        undef, $added_bug_id, $from_sprint_id, $to_sprint_id, $from_team_order, $to_team_order, $user_id, $now
    );
}

sub get_item_list_history {
    my $self = shift;
    my ($user_id, $pldt) = @_;

    my $dbh  = Bugzilla->dbh;
    my $sth = $dbh->prepare(
        "select
                bug_id,
                from_sprint_id,
                from_team_order,
                to_sprint_id,
                to_team_order
        from
	        scrums_item_list_history h1
        where
	        userid = ? and
                update_ts > ? and
                not exists 
        (select 
                null 
        from 
	        scrums_item_list_history h2
        where
                h2.userid = h1.userid and
                h2.update_ts > h1.update_ts)");
    $sth->execute($user_id, $pldt);
    my ($bug_id, $from_sprint_id, $from_team_order, $to_sprint_id, $to_team_order);
    ($bug_id, $from_sprint_id, $from_team_order, $to_sprint_id, $to_team_order) = $sth->fetchrow_array();

    return ($bug_id, $from_sprint_id, $from_team_order, $to_sprint_id, $to_team_order);
}

###############################
### Testing utility methods ###
###############################

# Method updates team order only in those items, that are in current (this) sprint or
# in product backlog. Any other sprints are considered inactive.
sub add_bug_into_sprint {
    my $self = shift;
    my ($added_bug_id, $insert_after_bug_id, $vars) = @_;
    if ($vars) { $vars->{'output'} .= "add_bug_into_sprint - added_bug_id:" . $added_bug_id . " insert_after_bug_id:" . $insert_after_bug_id . "<br />"; }

    # Possible values of 'insert_after_bug_team_order_number' are between -1 and team order of last item
    # If value is -1, 'new_bug_team_order_number' will become 0, which means, that added item will become first in list.
    my $new_bug_team_order_number = 1;
    if ($insert_after_bug_id) {
        my $item_order = Bugzilla::Extension::Scrums::Bugorder->new($insert_after_bug_id);
        $new_bug_team_order_number = $item_order->team_order() + 1;
    }

# TODO REFACTOR! CREATE NEW METHOD IS_BUG_MOVING_INTO_BIGGER_ORDER
    my $previous_team_order_for_bug = $self->_is_bug_in_team_order($added_bug_id, $vars);
    # Preceding bug 'insert_after_bug' moved one position. That is why added bug can be put into it's old position.
    # Index of insert_after_bug was searched by bug id after all.
    if ($previous_team_order_for_bug != -1 && $previous_team_order_for_bug < $new_bug_team_order_number) {
        $new_bug_team_order_number = $new_bug_team_order_number - 1;
    }

    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction();

    $self->add_bug_into_team_order($added_bug_id, $new_bug_team_order_number, $previous_team_order_for_bug, $vars);

    $dbh->bz_commit_transaction();
}

sub add_bug_into_team_order {
    my $self = shift;
    my ($dbh, $added_bug_id, $new_bug_team_order_number, $previous_team_order_for_bug, $vars) = @_;

    my $team = $self->get_team();
    my $previous_sprint_id_for_bug = $team->_is_bug_in_active_sprint($added_bug_id, $vars);
    if ($previous_sprint_id_for_bug) {
        $self->_update_sprint_map($added_bug_id, $previous_sprint_id_for_bug, $vars);
        $self->_save_team_order($added_bug_id, $new_bug_team_order_number, $previous_team_order_for_bug, $vars);
    }
    else {
        $dbh->do('INSERT INTO scrums_sprint_bug_map (bug_id, sprint_id) values (?, ?)', undef, $added_bug_id, $self->{'id'});

        if ($previous_team_order_for_bug) {
            # When bug is not in active sprint (backlog), it's team order is ignored even if it had team order
            $self->_save_team_order($added_bug_id, $new_bug_team_order_number, -1, $vars);
        }
        else {
            # When bug does not have team order, it needs to be inserted.
            $self->_save_team_order($added_bug_id, $new_bug_team_order_number, undef, $vars);
        }
    }
}

sub remove_bug_from_sprint {
    my $self = shift;
    my ($removed_bug_id, $vars) = @_;
    if ($vars) { $vars->{'output'} .= "remove_bug_from_sprint - removed_bug_id:" . $removed_bug_id . "<br />"; }

    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction();

    $self->_remove_sprint_map($removed_bug_id);
    my $item_order                    = Bugzilla::Extension::Scrums::Bugorder->new($removed_bug_id);
    my $removed_bug_team_order_number = $item_order->team_order();
    $self->_remove_bug_team_order($removed_bug_id, $vars);
    $self->_update_tail_team_order($removed_bug_team_order_number + 1, -1, $vars);    # increment is -1 => subtraction

    $dbh->bz_commit_transaction();
}

sub _update_sprint_map {
    my $self = shift;
    my ($added_bug_id, $previous_sprint_id_for_bug, $vars) = @_;
    if ($vars) { $vars->{'output'} .= "_update_sprint_map<br />"; }

    my $dbh = Bugzilla->dbh;
    $dbh->do(
        'UPDATE 
        scrums_sprint_bug_map 
    set
        bug_id = ?, 
        sprint_id = ?
    where
        bug_id = ? and
        sprint_id = ?',
        undef, $added_bug_id, $self->{'id'}, $added_bug_id, $previous_sprint_id_for_bug
            );
}

sub _remove_sprint_map {
    my $self = shift;
    my ($removed_bug_id, $vars) = @_;
    if ($vars) { $vars->{'output'} .= "_remove_sprint_map - removed_bug_id:" . $removed_bug_id . "<br />"; }

    my $dbh = Bugzilla->dbh;
    $dbh->do(
        'DELETE from 
        scrums_sprint_bug_map 
    where
        bug_id = ? and
        sprint_id = ?',
        undef, $removed_bug_id, $self->{'id'}
            );
}

sub _save_team_order {
    my $self = shift;
    my ($added_bug_id, $new_bug_team_order_number, $previous_team_order_for_bug, $vars) = @_;
    if ($vars) {
        $vars->{'output'} .=
            "_save_team_order - added_bug_id:"
          . $added_bug_id
          . " new_bug_team_order_number:"
          . $new_bug_team_order_number
          . " previous_team_order_for_bug:"
          . $previous_team_order_for_bug
          . "<br />";
    }

    # Possible values of 'new_bug_team_order_number' are between 1 and team order of last item plus one
    # If 'new_bug_team_order_number' is 1, added item will become first in list. Team orders start from 1.

    if (!$previous_team_order_for_bug) {
        $self->_update_tail_team_order($new_bug_team_order_number, 1, $vars);    # increment is 1 => addition
        $self->_insert_bug_team_order($added_bug_id, $new_bug_team_order_number, $vars);
    }
    elsif ($previous_team_order_for_bug eq -1) {
        $self->_update_tail_team_order($new_bug_team_order_number, 1, $vars);    # increment is 1 => addition
        $self->_update_bug_team_order($added_bug_id, $new_bug_team_order_number, $vars);
    }
    elsif ($previous_team_order_for_bug > $new_bug_team_order_number) {
        # Moving bug to smaller index (bigger priority) in team order list # increment is 1 => addition
        $self->_update_span_team_order($new_bug_team_order_number, $previous_team_order_for_bug, 1, $vars);
        $self->_update_bug_team_order($added_bug_id, $new_bug_team_order_number, $vars);
    }
    elsif ($previous_team_order_for_bug < $new_bug_team_order_number) {
        # Moving bug to bigger index (smaller priority) in team order list # increment is 1 => addition
        $self->_update_span_team_order($previous_team_order_for_bug + 1, $new_bug_team_order_number + 1, -1, $vars);
        $self->_update_bug_team_order($added_bug_id, $new_bug_team_order_number, $vars);
    }
    else {
        # New position = Old position => Do nothing
    }
}

sub _is_bug_in_team_order {
    my $self = shift;
    my ($ref_bug_id, $vars) = @_;

    my $team_order = undef;
    my $item_order = Bugzilla::Extension::Scrums::Bugorder->new($ref_bug_id);
    if ($item_order) {
        $team_order = $item_order->team_order();
        if (!$team_order && $item_order) {
            $team_order = -1;    # There is order definition for ref bug, but it does not contain team priority
        }
    }

    if ($vars) { $vars->{'output'} .= "_is_bug_in_team_order - ref_bug_id:" . $ref_bug_id . " result:" . $team_order . "<br />"; }
    return $team_order;
}

sub _update_tail_team_order {
    my $self = shift;
    my ($divider_team_order, $increment, $vars) = @_;
    if ($vars) { $vars->{'output'} .= "_update_tail_team_order - divider_team_order:" . $divider_team_order . "<br />"; }

    # Divider item is item which has smallest team order among items, that are moved.

    my $team   = $self->get_team();
    my $orders = $team->get_active_sprints_bug_orders();
    for my $item_order (@{$orders}) {
        if ($divider_team_order <= $item_order->team_order()) {
            $item_order->set_team_order($item_order->team_order() + $increment);
            $item_order->update();
        }
    }
}

sub _update_span_team_order {
    my $self = shift;
    my ($span_bigger_or_equal, $span_smaller_than, $increment, $vars) = @_;
    if ($vars) {
        $vars->{'output'} .= "_update_span_team_order - span_bigger_or_equal:" . $span_bigger_or_equal . " span_smaller_than:" . $span_smaller_than . "<br />";
    }

    my $team   = $self->get_team();
    my $orders = $team->get_active_sprints_bug_orders();
    for my $item_order (@{$orders}) {
        if ($span_bigger_or_equal <= $item_order->team_order() && $span_smaller_than > $item_order->team_order()) {
            $item_order->set_team_order($item_order->team_order() + $increment);
            $item_order->update();
        }
    }
}

sub _update_bug_team_order {
    my $self = shift;
    my ($added_bug_id, $new_team_order_number, $vars) = @_;
    if ($vars) {
        $vars->{'output'} .= "_update_bug_team_order - added_bug_id:" . $added_bug_id . " new_team_order_number:" . $new_team_order_number . "<br />";
    }

    my $item_order = Bugzilla::Extension::Scrums::Bugorder->new($added_bug_id);
    $item_order->set_team_order($new_team_order_number);
    $item_order->update();
}

sub _insert_bug_team_order {
    my $self = shift;
    my ($added_bug_id, $new_bug_team_order_number, $vars) = @_;
    if ($vars) {
        $vars->{'output'} .= "_insert_bug_team_order - added_bug_id:" . $added_bug_id . " new_bug_team_order_number:" . $new_bug_team_order_number . "<br />";
    }
    my $item_order = Bugzilla::Extension::Scrums::Bugorder->create({ bug_id => $added_bug_id, team => $new_bug_team_order_number });
}

sub _remove_bug_team_order {
    my $self = shift;
    my ($removed_bug_id, $vars) = @_;
    if ($vars) { $vars->{'output'} .= "_remove_bug_team_order - removed_bug_id:" . $removed_bug_id . "<br />"; }

    my $item_order = Bugzilla::Extension::Scrums::Bugorder->new($removed_bug_id);
    $item_order->set_team_order(undef);
    $item_order->update();
}

###############################
####      Accessors        ####
###############################

sub name               { return $_[0]->{'name'}; }
sub status             { return $_[0]->{'status'}; }
sub description        { return $_[0]->{'description'}; }
sub team_id            { return $_[0]->{'team_id'}; }
sub estimated_capacity { return $_[0]->{'estimated_capacity'}; }

sub get_team {
    my $self = shift;
    my $team = Bugzilla::Extension::Scrums::Team->new($self->team_id());
    return $team;
}

sub start_date {
    my $self = shift;
    return $self->{'start_date'};
}

sub end_date {
    my $self = shift;
    return $self->{'end_date'};
}

sub get_following_sprint {
    my ($self) = @_;

    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare('
        select 
	    id
        from 
	    scrums_sprints
        where 
	    start_date >= ? and
	    team_id = ? and
	    item_type = 1
        order by start_date asc limit 1');
    $sth->execute($self->end_date(), $self->team_id);
    my ($sprint_id) = $sth->fetchrow_array();
    my $sprint = undef;
    if ($sprint_id) {
        $sprint = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);
    }
    return $sprint;
}

sub is_current {
    my $self = shift;

    if (!$self->start_date() || !$self->end_date()) {
        return 0;
    }
    use Time::Local;
    my $now = time;
    my $yyyy;
    my $mm;
    my $dd;
    ($yyyy, $mm, $dd) = ($self->start_date() =~ /(\d+)-(\d+)-(\d+)/);
    my $sdate = timelocal(0, 0, 0, $dd, $mm - 1, $yyyy);
    ($yyyy, $mm, $dd) = ($self->end_date() =~ /(\d+)-(\d+)-(\d+)/);
    my $edate = timelocal(0, 0, 0, $dd, $mm - 1, $yyyy);

    if ($now >= $sdate and $now <= $edate) {
        return 1;
    }

    if ($edate <= $now) {
        # if there's no following sprint or it hasn't started yet then this is still the current
        my $following_sprint = $self->get_following_sprint();
        if ($following_sprint == undef) {
            return 1;
        }
        ($yyyy, $mm, $dd) = ($following_sprint->start_date() =~ /(\d+)-(\d+)-(\d+)/);
        my $fsdate = timelocal(0, 0, 0, $dd, $mm - 1, $yyyy);

        return $now < $fsdate;
    }
    return 0;
}

sub is_locked {
    my $self = shift;

    # Backlog is never locked
    if ($_[0]->{'item_type'} == 2) {
        return 0;
    }

    # If there is following sprint, sprint has been archived and is locked
    my $following = $self->get_following_sprint();
    if ($following) {
        return 1;
    }
    else {
        return 0;
    }
}

1;

__END__

