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
use constant LIST_ORDER => 'nominal_schedule';

use constant DB_COLUMNS => qw(
  id
  team_id
  name
  nominal_schedule
  status
  is_active
  description
  start_date
  end_date
  estimated_capacity
  );

use constant REQUIRED_CREATE_FIELDS => qw(
  team_id
  name
  nominal_schedule
  status
  is_active
  );

use constant UPDATE_COLUMNS => qw(
  name
  nominal_schedule
  status
  is_active
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

sub validate_date {
    my ($self, $this_id, $team_id, $tested_date) = @_;

    my $err = Bugzilla::Extension::Scrums::Sprint->_check_date($this_id, $team_id, $tested_date);
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

###############################
####       Methods         ####
###############################

sub get_bugs {
    my $self = shift;
    if (!$self->{'my_bugs'}) {
        $self->set('my_bugs', $self->_fetch_bugs());
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
	    s2.nominal_schedule > s1.nominal_schedule and
	    s2.nominal_schedule < ? and
	    s2.team_id = ? and
	    s2.item_type = 1)
        and 
	    s1.nominal_schedule < ? and
	    s1.team_id = ? and
	    s1.item_type = 1');
    $sth->execute($self->nominal_schedule, $self->team_id, $self->nominal_schedule, $self->team_id);
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
    push @sprint_hist1,     'Sprint current-1';
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
        push @sprint_hist2,     'Sprint current-2';
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
            push @sprint_hist3,     'Sprint current-3';
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

sub _fetch_bugs {
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
        bo.team,
        b.assigned_to,
        sum(work_time) as work_done
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

sub set_name               { $_[0]->set('name',               $_[1]); }
sub set_nominal_schedule   { $_[0]->set('nominal_schedule',   $_[1]); }
sub set_status             { $_[0]->set('status',             $_[1]); }
sub set_is_active          { $_[0]->set('is_active',          $_[1]); }
sub set_description        { $_[0]->set('description',        $_[1]); }
sub set_start_date         { $_[0]->set('start_date',         $_[1]); }
sub set_end_date           { $_[0]->set('end_date',           $_[1]); }
sub set_estimated_capacity { $_[0]->set('estimated_capacity', $_[1]); }

###############################
### Testing utility methods ###
###############################

sub add_bug_into_sprint {
    my $self = shift;
    my ($added_bug_id, $preceding_bug_id) = @_;

    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction();

    my $sth1 = $dbh->prepare(
        'select 
        team 
    from
        scrums_bug_order
    where
        bug_id = ?'
                            );
    $sth1->execute($preceding_bug_id);
    my ($preceding_team) = $sth1->fetchrow_array;

    $dbh->do('INSERT INTO scrums_sprint_bug_map (bug_id, sprint_id) values (?, ?)', undef, $added_bug_id, $self->{'id'});

    $dbh->do(
        'update
        scrums_bug_order bo
    set
        team = team + 1
    where exists
    (select null from
        scrums_sprint_bug_map sbm
    inner join
        scrums_sprints s
    on
        s.id = sbm.sprint_id and
        s.team_id = ? and
        s.is_active = 1
    where
        sbm.bug_id = bo.bug_id and
        team > ?)', undef, $self->{'team_id'}, $preceding_team
    );

    $dbh->do('INSERT INTO scrums_bug_order (bug_id, team) values (?, ?)', undef, $added_bug_id, $preceding_team + 1);

    $dbh->bz_commit_transaction();
}

###############################
####      Accessors        ####
###############################

sub name               { return $_[0]->{'name'}; }
sub status             { return $_[0]->{'status'}; }
sub is_active          { return $_[0]->{'is_active'}; }
sub description        { return $_[0]->{'description'}; }
sub team_id            { return $_[0]->{'team_id'}; }
sub estimated_capacity { return $_[0]->{'estimated_capacity'}; }

sub nominal_schedule {
    my $self = shift;
    return $self->{'nominal_schedule'};
}

sub start_date {
    my $self = shift;
    return $self->{'start_date'};
}

sub end_date {
    my $self = shift;
    return $self->{'end_date'};
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

    return ($now >= $sdate and $now <= $edate);
}

1;

__END__

