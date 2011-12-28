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
                        (start_date >= ? or start_date is null) and 
                        (end_date <= ? or end_date is null) and 
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
    my $work_done = 0;
    my ($temp) = $sth->fetchrow_array();
    if ($temp) {
        $work_done = $temp;
    }
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
        if (@$bug[9] == $member_id) {
            $cum_member_workload = $cum_member_workload + @$bug[11];
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
    my $prediction = 0;
    my $work_done  = 0;
    $work_done = $self->get_work_done();
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
        sbm.bug_id
    from
	scrums_sprint_bug_map sbm
    inner join
        scrums_bug_order bo
    on
        bo.bug_id = sbm.bug_id
    where
	sprint_id = ?
    order by
        team asc', undef, $self->id
    );
    my @array;
    for my $row (@{$sprint_items}) {
        push(@array, @{$row}[0]);
    }
    return \@array;
}

sub get_remaining_item_array {
    my $self = shift;
    my $dbh  = Bugzilla->dbh;
    my ($sprint_items) = $dbh->selectall_arrayref(
        'select
        sbm.bug_id
    from
	scrums_sprint_bug_map sbm
    inner join
        scrums_bug_order bo
    on
        bo.bug_id = sbm.bug_id
    inner join
        bugs b
    on
        sbm.bug_id = b.bug_id
    inner join
        bug_status bs
    on
        b.bug_status = bs.value
    where
	sprint_id = ? and
        bs.is_open = 1
    order by
        team asc', undef, $self->id
    );
    my @array;
    for my $row (@{$sprint_items}) {
        push(@array, @{$row}[0]);
    }
    return \@array;
}

sub get_biggest_team_order {
    my $self = shift;

    my $item_array      = $self->get_item_array();
    my $number_of_items = (scalar @{$item_array});
    if ($number_of_items > 0) {
        my $li                 = -1;
        my $last               = @{$item_array}[$li];
        my $biggest_order_item = Bugzilla::Extension::Scrums::Bugorder->new($last);
        return $biggest_order_item->team_order();
    }
    else {
        return 0;    # No items in sprint
    }
}

sub is_item_in_sprint {
    my $self = shift;
    my ($bug_id) = @_;

    my $item_array = $self->get_item_array();
    my @matches = grep { $_ eq $bug_id } @{$item_array};
    return ((scalar @matches) > 0);
}

sub get_blocking_item_list {
    # Method is class method. Self is null.
    my ($self, $bug_id) = @_;
    my @blocking_list;
    my @items_to_be_checked;
    push (@items_to_be_checked, $bug_id);
    while (scalar @items_to_be_checked > 0) {
        my $temp_id = shift (@items_to_be_checked);
        my $bug = Bugzilla::Bug->new($temp_id);
        my $bug_blocking = $bug->dependson();
        for my $blocking (@{$bug_blocking}) {
            push (@items_to_be_checked, $blocking);
            push (@blocking_list, $blocking);
        }
    }
    return \@blocking_list;
}

sub set_name               { $_[0]->set('name',               $_[1]); }
sub set_status             { $_[0]->set('status',             $_[1]); }
sub set_description        { $_[0]->set('description',        $_[1]); }
sub set_start_date         { $_[0]->set('start_date',         $_[1]); }
sub set_end_date           { $_[0]->set('end_date',           $_[1]); }
sub set_estimated_capacity { $_[0]->set('estimated_capacity', $_[1]); }

sub initialise_with_old_bugs {
    my $self                 = shift;
    my ($bug_array)          = @_;
    my $dbh                  = Bugzilla->dbh;
    my $number_of_added_bugs = scalar @{$bug_array};

    my $team    = $self->get_team();
    my $orders  = $team->get_active_sprints_bug_orders();
    my $counter = 1;
    for my $item_order (@{$orders}) {
        $item_order->set_team_order($counter + $number_of_added_bugs);
        $item_order->update();
        $counter = $counter + 1;
    }
    $counter = 1;
    for my $bug (@{$bug_array}) {
        my $bug_id = $bug->id();
        $dbh->do('INSERT INTO scrums_sprint_bug_map (bug_id, sprint_id) values (?, ?)', undef, $bug_id, $self->{'id'});
        my $item_order = Bugzilla::Extension::Scrums::Bugorder->new($bug_id);
        $item_order->set_team_order($counter);
        $item_order->update();
        $counter = $counter + 1;
    }
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
    if ($insert_after_bug_id && $self->is_item_in_sprint($insert_after_bug_id)) {
        my $item_order = Bugzilla::Extension::Scrums::Bugorder->new($insert_after_bug_id);
        $new_bug_team_order_number = $item_order->team_order() + 1;
    }
    else {
        $new_bug_team_order_number = $self->get_biggest_team_order() + 1;
    }

    # TODO REFACTOR! CREATE NEW METHOD IS_BUG_MOVING_INTO_BIGGER_ORDER
    my $previous_team_order_for_bug = $self->_is_bug_in_team_order($added_bug_id, $vars);
    # Preceding bug 'insert_after_bug' moved one position. That is why added bug can be put into it's old position.
    # Index of insert_after_bug was searched by bug id after all.
    if ($previous_team_order_for_bug && $previous_team_order_for_bug != -1 && $previous_team_order_for_bug < $new_bug_team_order_number) {
        $new_bug_team_order_number = $new_bug_team_order_number - 1;
    }

    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction();

    $self->add_bug_into_team_order($dbh, $added_bug_id, $new_bug_team_order_number, $previous_team_order_for_bug, $vars);

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

1;

__END__


=head1 NAME

Bugzilla::Extension::Scrums::Sprint - Scrums sprint class.

=head1 SYNOPSIS

    use Bugzilla::Extension::Scrums::Sprint;
    my $sprint = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);

    $sprint->name(); 
    $sprint->status();
    $sprint->description();
    $sprint->team_id();
    $sprint->estimated_capacity();
    $sprint->get_team();
    $sprint->start_date();
    $sprint->end_date();
    $sprint->get_following_sprint();
    $sprint->is_current();

    $sprint->check_start_date($start_date);
    $sprint->check_end_date($end_date);
    $sprint->validate_span($this_id, $team_id, $span_start_date, $span_end_date);

    $sprint->get_bugs();
    $sprint->get_work_done();
    $sprint->get_capacity_summary();
    $sprint->calculate_remaining();
    $sprint->get_member_capacity($member_id);
    $sprint->get_member_workload($member_id);
    $sprint->get_person_capacity();
    $sprint->get_previous_sprint();
    $sprint->get_predictive_estimate();
    $sprint->get_items();
    $sprint->get_item_array();
    $sprint->get_remaining_item_array();
    $sprint->get_biggest_team_order();
    $sprint->is_item_in_sprint($bug_id);
    $sprint->initialise_with_old_bugs($bug_array);

    $sprint->add_bug_into_sprint($added_bug_id, $insert_after_bug_id, $vars);
    $sprint->add_bug_into_team_order($dbh, $added_bug_id, $new_bug_team_order_number, $previous_team_order_for_bug, $vars);
    $sprint->remove_bug_from_sprint($removed_bug_id, $vars);

    my $sprint = Bugzilla::Extension::Scrums::Sprint->create({ team_id => $team_id, name => $name, status => $status, item => $item });

    $sprint->set_name($name);
    $sprint->set_status($status);
    $sprint->set_description($description);
    $sprint->set_start_date($start_date);
    $sprint->set_end_date($end_date);
    $sprint->set_estimated_capacity($estimated_capacity);
    $sprint->set_member_capacity($user_id, $capacity);

    $sprint->update();

    $sprint->remove_from_db;

=head1 DESCRIPTION

Sprint object represent either sprint or team backlog. These two applications have similar structure except that backlog does not have
start and end dates. Item type separates these two applications of this same class.


=head1 METHODS

=over

=item C<new($spint_id)>

 Description: The constructor is used to load an existing sprint (backlog)
              by passing a sprint ID.

 Params:      $param - Sprint id from the database that we want to
                       read in (integer). 

 Returns:     A Bugzilla::Extension::Scrums::Sprint object.

=item C<name()>

 Description: Returns name of the sprint.

 Params:      none.

 Returns:     Sprint name (string).

=item C<status()>

 Description: Returns status of the sprint.

 Params:      none.

 Returns:     Sprint status (string).

=item C<description()>

 Description: Returns description of the sprint.

 Params:      none.

 Returns:     Sprint description (string).

=item C<team_id()>

 Description: Returns id of the team, that owns the sprint.

 Params:      none.

 Returns:     Id (integer) of a Bugzilla::Extension::Scrums::Team object.

=item C<estimated_capacity()>

 Description: Returns estimate about capacity, that is availabe for implementing sprint.

 Params:      none.

 Returns:     Capacity estimate (decimal number with two fractional digits).

=item C<get_team()>

 Description: Returns team that owns the sprint.

 Params:      none.

 Returns:     A Bugzilla::Extension::Scrums::Team object.

=item C<start_date()>

 Description: Returns starting date of the sprint.

 Params:      none.

 Returns:     Starting date (string in format 'yyyy-mm-dd').

=item C<end_date()>

 Description: Returns ending date of the sprint.

 Params:      none.

 Returns:     Ending date (string in format 'yyyy-mm-dd').

=item C<get_following_sprint()>

 Description: Returns sprint, that follows after this sprint. Starting date is used as sorting criteria.

 Params:      none.

 Returns:     A Bugzilla::Extension::Scrums::Sprint object.

=item C<is_current()>

 Description: Returns whether sprint is current ie. most recent sprint of the team, that it belongs.

 Params:      none.

 Returns:     One if true and zero if false.

=item C<check_start_date($start_date)>

 Description: Checks whether start date overlaps another sprint of the same team.

 Params:      none.

 Returns:     Nothing. Throws error, if start date overlaps another sprint of the same team

=item C<check_end_date($end_date)>

 Description: Checks whether end date overlaps another sprint of the same team.

 Params:      none.

 Returns:     Nothing. Throws error, if end date overlaps another sprint of the same team

=item C<get_bugs()>

 Description: Returns all items, that belong to sprint.

 Params:      none.

 Returns:     Reference to a table of data, that represents list of bugs.

=item C<get_item_array()>

 Description: Returns the ids of items, that belong to sprint. Items are sorted by team priority order.

 Params:      none.

 Returns:     Reference to an array of ids of Bugzilla::Bug objects (integers).

=item C<get_remaining_item_array()>

 Description: Returns the ids of items, that belong to sprint and are open. Items are sorted by team priority order.

 Params:      none.

 Returns:     Reference to an array of ids of Bugzilla::Bug objects (integers).

=item C<is_item_in_sprint($bug_id)>

 Description: Returns whether given item is in sprint or not.

 Params:      Id (integer) of Bugzilla::Bug object representing tested bug.

 Returns:     One if true and zero if false.

=item C<get_biggest_team_order()>

 Description: Returns biggest (last) team order of all items in sprint.

 Params:      none.

 Returns:     Integer.

=item C<get_work_done()>

 Description: Returns the sum of work, that has been reported to items in sprint.

 Params:      none.

 Returns:     Number of hours (decimal number with two fractional digits).

=item C<get_capacity_summary()>

 Description: Returns summary of reported hours in sprint and estimates of amount of work and capacity.

 Params:      none.

 Returns:     Reference to a hash table, that contains following keys: 'sprint_capacity', 'work_done', 'remaining_work', 'total_work', 'free_capacity'

=item C<calculate_remaining()>

 Description: Returns sum of remaining work in sprint.

 Params:      none.

 Returns:     Number of hours (decimal number with two fractional digits).

=item C<get_member_capacity($member_id)>

 Description: Returns capacity, that team member is estimated to put into sprint. Capacity is measured as a fraction of one. Capacity of one equals 100% effort.

 Params:      Id (integer) of a Bugzilla::User object.

 Returns:     Capacity between 0-1 (decimal number with two fractional digits).

=item C<get_member_workload($member_id)>

 Description: Returns the sum of work in those items in sprint, that have been assigned to given user.

 Params:      Id (integer) of a Bugzilla::User object.

 Returns:     Number of hours (decimal number with two fractional digits).

=item C<get_person_capacity()>

 Description: Returns the number of people, who have been allocated to sprint. Number of individuals is weighted with estimated capacity in sprint of each person. 

 Params:      none.

 Returns:     Number of people (decimal number with two fractional digits).

=item C<get_previous_sprint()>

 Description: Returns another sprint of same team, that precedes this sprint.

 Params:      none.

 Returns:     A Bugzilla::Extension::Scrums::Sprint obejct.

=item C<get_predictive_estimate()>

 Description: Returns work amount and person capacity history of maximum three previous sprints starting from this sprint. Estimate of avarage sprint is created from median of three sprints.

 Params:      none.

 Returns:     Reference to hash map, that contains keys 'prediction' and history'. 'Prediction' is number of hours. 'History' contains table of three sprints with sprint name, work hours and number of people.

=item C<set_name($name)>

 Description: Sets name of the sprint.

 Params:      Name of sprint (string).

 Returns:     Nothing.

=item C<set_status($status)>

 Description: Sets status of the sprint.

 Params:      Status of sprint (string).

 Returns:     Nothing.

=item C<set_description($description)>

 Description: Sets description of the sprint.

 Params:      Description of sprint (string).

 Returns:     Nothing.

=item C<set_start_date($start_date)>

 Description: Sets starting date of the sprint.

 Params:      Starting date (string in format 'yyyy-mm-dd').

 Returns:     Nothing.

=item C<set_end_date($end_date)>

 Description: Sets ending date of the sprint.

 Params:      Starting date (string in format 'yyyy-mm-dd').

 Returns:     Nothing.

=item C<set_estimated_capacity($estimated_capacity)>

 Description: Sets capacity estimate of the sprint.

 Params:      Number of hours (decimal number with two fractional digits).

 Returns:     Nothing.

=item C<set_member_capacity($user_id, $capacity)>

 Description: Sets capacity, that given team member is estimated to put into sprint. Capacity is measured as a fraction of one. Capacity of one equals 100% effort.

 Params:      $user_id  - Id (integer) of a Bugzilla::User object.
              $capacity - Decimal number with two fractional digits

 Returns:     Nothing.


=item C<initialise_with_old_bugs()>

 Description: Puts open bugs from previous sprint into newly created sprint as starting point.

 Params:      $bug_array - Reference to array of Bugzilla::Bug objects.

 Returns:     Nothing.


=item C<add_bug_into_sprint($added_bug_id, $insert_after_bug_id, $vars)>

 Description: Adds given bug into sprint into given position. Updates also team order accordingly because all items in sprints always have team order. Sprint and team order are updated inside single transaction.

 Params:      $added_bug_id        - Id (integer) of Bugzilla::Bug object representing added item
              $insert_after_bug_id - Id (integer) of Bugzilla::Bug object representing preceding item in team order list
              $vars                - Optional, used for debug printing

 Returns:     Nothing.

=item C<add_bug_into_team_order($dbh, $added_bug_id, $new_bug_team_order_number, $previous_team_order_for_bug, $vars)>

 Description: Adds given bug into team order inside given transaction. Added item can already be in given team order in different position or item can be new to team order. Adding a new item into team order includes also updating other items in same team order by shifting them one position.

 Params:      $dbh                         - Database handle, that contains open transaction
              $added_bug_id                - Id (integer) of Bugzilla::Bug object representing added item
              $new_bug_team_order_number   - Order (integer) of added item in team order
              $previous_team_order_for_bug - Previous order (integer) of added item if given item was already previously in same team order. Undef, if item was not in same team order before adding.
              $vars                        - Optional, used for debug printing

 Returns:     Nothing.

=item C<remove_bug_from_sprint($removed_bug_id, $vars)>

 Description: Removes given item from sprint. Updates also team order accordingly because all items in sprints always have team order. Sprint and team order are updated inside single transaction.

 Params:      $removed_bug_id                - Id (integer) of Bugzilla::Bug object representing removed item
              $vars                          - Optional, used for debug printing

 Returns:     Nothing.

=back

=head1 CLASS METHODS

=over

=item C<create(\%params)>

 Description: Creates a new sprint.

 Params:      The hashref must have the following keys:
              team_id            - Id (integer) of owner team
              name               - Name of the sprint (string). This name
                                   should be unique inside same team.
              status             - Status of the sprint (string).
              The following keys are optional:
              description        - Description of sprint (string).
              start_date         - Starting date of the sprint (string in format 'yyyy-mm-dd')
              end_date           - Ending date of the sprint (string in format 'yyyy-mm-dd')
              estimated_capacity - Number of hours, that are estimated to be put into sprint (decimal number with two fractional digits)

 Returns:     A Bugzilla::Extension::Scrums::Sprint object.

=item C<validate_span($this_id, $team_id, $span_start_date, $span_end_date)>

 Description: Returns whether given timespan overlaps some existing sprint is a way, that is not possible to detect solely from single start and endpoints only.

 Params:      $this_id           - Optional, id (integer) of checked sprint. This is given only, if checked sprint is already in database. This is to avoid detecting collision with sprint itself.
              $team_id           - Id (integer) of team, that owns the sprint. Sprints of other teams are ignored.
              $span_start_date   - Start date of tested timespan
              $span_end_date     - End date of tested timespan

 Returns:     One if true and zero if false.

=back

=cut

