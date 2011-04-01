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

package Bugzilla::Extension::Scrums::Sprintslib;

use lib qw(./extensions/Scrums/lib);

use Bugzilla::Extension::Scrums::Bugorder;

use Bugzilla::FlagType;
use Bugzilla::Error;
use Bugzilla::Util qw(trick_taint);

use JSON::XS;

use strict;
use base qw(Exporter);

# This file can be loaded by your extension via
# "use Bugzilla::Extension::Scruns::Releases". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)
our @EXPORT = qw(
  update_bug_order_from_json
  );
#
# Important!
# Data needs to be in exact format:
#
#  { -1 : [1,2,3,4,5], 18 : [10,11,12] } 
#

sub update_bug_order_from_json {
    my ($team_id, $data) = @_;

    my $json = new JSON::XS;
    if ($data =~ /(.*)/) {
        $data = $1;    # $data now untainted
    }
    my $content = $json->allow_nonref->utf8->relaxed->decode($data);

    my %all_team_sprints_and_unprioritised_in = %{$content};
    team_bug_order($team_id, $content);
}

sub team_bug_order {
    my ($team_id, $all_team_sprints_and_unprioritised_in) = @_;

    my %sprints_hash;
#    my %team_order_hash;

    _get_sprints_hash(\%sprints_hash, $team_id);
#    _get_team_order_hash(\%team_order_hash, $team_id);

    my @sprint_id_array = keys %{$all_team_sprints_and_unprioritised_in};
    for my $sprint_id (@sprint_id_array)
    {
        my $bugs = $all_team_sprints_and_unprioritised_in->{$sprint_id};

        if ($sprint_id == -1) {
            process_unprioritised_in($bugs);
        }
        else {
            process_sprint($sprint_id, $bugs, \%sprints_hash);
        }
    }

#    process_team_orders($all_team_sprints_and_unprioritised_in, \%team_order_hash);
    process_team_orders($all_team_sprints_and_unprioritised_in);
}

sub process_sprint() {
    my ($sprint_id, $bugs, $sprints_hash) = @_;

    # print "Processing sprint\n";
    foreach my $bug (@{$bugs}) {
        my $old_sprint = $sprints_hash->{$bug};

        if ($old_sprint == $sprint_id) {
            # print "(Sprint is unchanged)\n";
        }
        elsif ($old_sprint == 0) {
            Bugzilla->dbh->do('INSERT INTO scrums_sprint_bug_map (bug_id, sprint_id) values (?, ?)', undef, $bug, $sprint_id);
        }
        else {
            Bugzilla->dbh->do('UPDATE scrums_sprint_bug_map set sprint_id=? where bug_id=?', undef, $sprint_id, $bug);
        }
    }
}

sub process_unprioritised_in() {
    my ($unprioritised_in) = @_;

    foreach my $bug (@{$unprioritised_in}) {
        Bugzilla->dbh->do('DELETE from scrums_sprint_bug_map where bug_id=?',         undef, $bug);
        Bugzilla->dbh->do('UPDATE scrums_bug_order set team = NULL where bug_id = ?', undef, $bug);
    }
}

sub process_team_orders() {
#    my ($ref, $team_order_hash) = @_;
    my ($ref) = @_;

    my %all_team_sprints_and_unprioritised_in = %{$ref};

    my $counter = 1;

    my @sprint_id_array = keys %all_team_sprints_and_unprioritised_in;
    for my $sprint_id (@sprint_id_array)
    {
        my $bugs = $all_team_sprints_and_unprioritised_in{$sprint_id};


        # This means, that table is sprint and not unprioritised_in
        if ($sprint_id != -1) {
            foreach my $bug (@{$bugs}) {
#                my $old_team_order = $team_order_hash->{$bug};
#                if (!exists $team_order_hash->{$bug}) {
                my $old_team_order = _old_team_order($bug);
#                if (!_exists_bug_order($bug->id());
                if ($old_team_order == -1) {
                    Bugzilla->dbh->do('INSERT INTO scrums_bug_order (bug_id, team) values (?, ?)', undef, $bug, $counter);
                }
                elsif ($counter != $old_team_order) {
                    Bugzilla->dbh->do('UPDATE scrums_bug_order set team=? where bug_id=?', undef, $counter, $bug);
                }
                else {
                    # Team order for bug ($bug) is unchanged ($old_team_order)
                }
                $counter = $counter + 1;
            }
        }
        # Unprioritised_in must be handled separately
        # Table scrums_bug_order is however updated for unprioritised_in at the same time as scrums_sprint_bug_map, because order in table is irrelevant.
    }
}

sub _old_team_order {
    my ($bug_id) = @_;

    my ($item_id, $team_order) = Bugzilla->dbh->selectrow_array('SELECT bug_id, team FROM scrums_bug_order WHERE bug_id = ?', undef, $bug_id);
    if ($item_id) {
        return $team_order;
    }        
    return -1;
}

sub _get_sprints_hash {
    my ($sprints_hash, $team_id) = @_;

    my $dbh = Bugzilla->dbh;
    my $sth = $dbh->prepare(
        "select
	sbm.bug_id as bug_id,
	spr.id as sprint
    from 
	scrums_sprint_bug_map sbm
    inner join 
	scrums_sprints spr on sbm.sprint_id = spr.id
    where 
        spr.is_active = 1 and
	spr.team_id = ?");
    trick_taint($team_id);
    $sth->execute($team_id);

    while (my $row = $sth->fetchrow_arrayref) {
        my ($bug_id, $sprint) = @$row;
        $sprints_hash->{$bug_id} = $sprint;
    }
}

## First part of union contains team bugs, that are scheduled. All scheduled bugs
## have bug order.
## Second part of union contains bugs, that are both possible to schedule and
## contain bug order in database (bug order is in this case null, because bugs are unprioritised)
## Bug is possible to schedule, when it is unprioritised and open.
## Some of such bugs contains bug order in database and some don't.
#sub _get_team_order_hash {
#    my ($team_order_hash, $team_id) = @_;
#
#    my $dbh = Bugzilla->dbh;
#    my $sth = $dbh->prepare(
#        "(select 
#	b.bug_id as bug_id,
#	bo.team as team
#    from 
#	scrums_componentteam sct
#    inner join
#	bugs b on b.component_id = sct.component_id
#    inner join
#	scrums_bug_order bo on b.bug_id = bo.bug_id
#    where 
#	sct.teamid = ?)
#    union
#    (select
#	b.bug_id as bug_id,
#	bo.team as team
#    from 
#	scrums_componentteam sct
#    inner join
#	bugs b on b.component_id = sct.component_id
#    inner join
#	scrums_bug_order bo on b.bug_id = bo.bug_id
#    inner join
#	bug_status bs on b.bug_status = bs.value
#    where 
#	sct.teamid = ? and
#	bs.is_open = 1 and
#        not exists (select null from scrums_sprint_bug_map sbm inner join scrums_sprints spr on sbm.sprint_id = spr.id where b.bug_id = sbm.bug_id and spr.team_id = ?))
#    order by 
#	team, bug_id"
#                           );
#    trick_taint($team_id);
#    $sth->execute($team_id, $team_id, $team_id);
#
#    while (my $row = $sth->fetchrow_arrayref) {
#        my ($bug_id, $team_order) = @$row;
#        $team_order_hash->{$bug_id} = $team_order;
#    }
#}

1;
