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

package Bugzilla::Extension::Scrums::Teamorderlib;

use lib qw(./extensions/Scrums/lib);

use Bugzilla::Extension::Scrums::Bugorder;

use Bugzilla::FlagType;
use Bugzilla::Error;
use Bugzilla::Util qw(trick_taint);

use JSON::XS;
use Date::Parse;

use strict;
use base qw(Exporter);

# This file can be loaded by your extension via
# "use Bugzilla::Extension::Scruns::Releases". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)
our @EXPORT = qw(
  update_bug_order_from_json
  insert_item_list_into_sprint
  );

#
# Important!
# Data needs to be in exact format:
#
#  { -1 : [1,2,3,4,5], 18 : [10,11,12] }
#
sub update_bug_order_from_json {
    my ($team_id, $data, $vars) = @_;

    my $json = new JSON::XS;
    if ($data =~ /(.*)/) {
        $data = $1;    # $data now untainted
    }
    my $content = $json->allow_nonref->utf8->relaxed->decode($data);

    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction();

    my $err;
    my $warning;
    ($err, $warning) = team_bug_order($team_id, $content);

    if (!$err) {
        $dbh->bz_commit_transaction();
    }
    else {
        $vars->{'errors'} = "Collision in database update. Refresh page to update data. " . $err;
    }
    $vars->{'warnings'} = $warning;
}

sub team_bug_order {
    my ($team_id, $content) = @_;

    my ($err, $warning);

    my $all_team_sprints_and_unprioritised_in = $content->{"data_lists"};
    my $original_sprints                      = $content->{"original_lists"};
    my %sprints_hash;
    my %lengths_hash;
    my %old_order_hash;

    _get_sprints_hashes($team_id, \%sprints_hash, \%lengths_hash);
    my $order_is_consistent = _check_team_order($team_id);
    my @active_sprints;
    my $unprioritised_in_bugs;
    my @sprint_id_array = keys %{$all_team_sprints_and_unprioritised_in};
    for my $sprint_id (@sprint_id_array) {
        my $bugs = $all_team_sprints_and_unprioritised_in->{$sprint_id};

        if ($sprint_id == -1) {
            $unprioritised_in_bugs = $bugs;
        }
        else {
            process_sprint($sprint_id, $bugs, \%sprints_hash);
            push @active_sprints, $sprint_id;
        }
    }

    # Team orders are processed first. Reason is, that uprioritised_in changes also team order.
    # Process_team_orders function stores initial values of team order into hash map
    process_team_orders($all_team_sprints_and_unprioritised_in, $original_sprints, \%old_order_hash);

    process_unprioritised_in($unprioritised_in_bugs, \@active_sprints);
    if ($order_is_consistent == 1) {
        $err = _compare_to_original_values($original_sprints, \%sprints_hash, \%lengths_hash, \%old_order_hash);
    }
    else {
        $warning = "Inconsistency detected in team order. If situation persists, contact system administrator";
    }
    return ($err, $warning);
}

sub _check_team_order {
    my ($team_id) = @_;

    my $dbh         = Bugzilla->dbh;
    my $team        = Bugzilla::Extension::Scrums::Team->new($team_id);
    my $ref_counter = 1;
    my $order_from_database;

    my $sprint = $team->get_team_current_sprint();
    if ($sprint) {
        my ($sprint_items) = $dbh->selectall_arrayref(
            'select
            sbm.bug_id,
            team
        from
	    scrums_sprint_bug_map sbm
        left join
            scrums_bug_order bo
        on
            bo.bug_id = sbm.bug_id
        where
	    sprint_id = ?
        order by
            team asc', undef, $sprint->id()
        );

        for my $row (@{$sprint_items}) {
            $order_from_database = @{$row}[1];
            if ($order_from_database != $ref_counter) {
                return 0;
            }
            $ref_counter++;
        }
    }

    my $backlog = $team->get_team_backlog();
    my ($backlog_items) = $dbh->selectall_arrayref(
        'select
        sbm.bug_id,
        team
    from
	scrums_sprint_bug_map sbm
    left join
        scrums_bug_order bo
    on
        bo.bug_id = sbm.bug_id
    where
	sprint_id = ?
    order by
        team asc', undef, $backlog->id()
    );

    for my $row (@{$backlog_items}) {
        $order_from_database = @{$row}[1];
        if ($order_from_database != $ref_counter) {
            return 0;
        }
        $ref_counter++;
    }
    return 1;
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
            Bugzilla->dbh->do('UPDATE scrums_sprint_bug_map set sprint_id=? where bug_id=? and sprint_id=?', undef, $sprint_id, $bug, $old_sprint);
        }
    }
}

sub process_unprioritised_in() {
    my ($unprioritised_in, $active_sprints) = @_;

    # Unprioritised_in must be handled separately
    # Table scrums_bug_order is however updated for unprioritised_in at the same time as scrums_sprint_bug_map, because order in table is irrelevant.
    foreach my $bug (@{$unprioritised_in}) {
        Bugzilla->dbh->do('DELETE from scrums_sprint_bug_map where bug_id=? and (sprint_id = ? or sprint_id = ?)',
                          undef, $bug,
                          @{$active_sprints}[0],
                          @{$active_sprints}[1]);
        Bugzilla->dbh->do('UPDATE scrums_bug_order set team = NULL where bug_id = ?', undef, $bug);
    }
}

sub process_team_orders() {
    my ($updated_sprints_and_unprioritised_in, $originals, $old_order_hash) = @_;

    my %all_team_sprints_and_unprioritised_in = %{$updated_sprints_and_unprioritised_in};
    my %original_sprints                      = %{$originals};

    my $counter = 1;

    my @sprint_id_array = keys %all_team_sprints_and_unprioritised_in;
    # Sprints need to be processed in pre-defined order.
    # This is important, because team order is otherwise wrong.
    @sprint_id_array = sort { $a < $b } @sprint_id_array;
    for my $sprint_id (@sprint_id_array) {
        my $bugs = $all_team_sprints_and_unprioritised_in{$sprint_id};

        # This means, that table is sprint and not unprioritised_in
        if ($sprint_id != -1) {
            foreach my $bug (@{$bugs}) {
                # Old values of team order need to be fetch one bug at a time.
                # This is because it is not possible to know in advance, which bugs user has added to sprint.
                # Even if bug has not previously been in sprint, it might have record in scrums_bug_order.
                my $old_team_order = _old_team_order($bug);
                $old_order_hash->{$bug} = $old_team_order;
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

        # Unprioritised_in does not have team order anymore, but originally it had.
        # Old values are stored for comparison.
        if ($sprint_id == -1) {
            foreach my $bug (@{$bugs}) {
                my $old_team_order = _old_team_order($bug);
                $old_order_hash->{$bug} = $old_team_order;
            }
        }
    }
}

sub insert_item_list_into_sprint {
    my ($data, $vars) = @_;

    my $json = new JSON::XS;
    if ($data =~ /(.*)/) {
        $data = $1;    # $data now untainted
    }
    my $content         = $json->allow_nonref->utf8->relaxed->decode($data);
    my $pending_items   = $content->{"pending_items"};
    my $moved_bug_id    = $content->{"bug_id"};
    my $sprint_id       = $content->{"list_id"};
    my $insert_after_id = $content->{"insert_after_id"};

    my $sprint    = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);
    my $put_first = 0;
    if ($insert_after_id == 0) {
        $put_first = 1;
    }

    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction();

    $sprint->insert_into_sprint($dbh, $moved_bug_id, $insert_after_id, $put_first, $vars);
    for my $added_bug_id (@{$pending_items}) {
        $sprint->insert_into_sprint($dbh, $added_bug_id, $insert_after_id, $put_first, $vars);
    }

    $dbh->bz_commit_transaction();
}

sub _compare_to_original_values {
    my ($original_sprints_ref, $sprints_hash, $lengths_hash, $old_order_hash) = @_;

    my %original_sprints = %{$original_sprints_ref};
    my @sprint_id_array  = keys %original_sprints;

    my $original_list_counter = 1;

    # Sprints need to be processed in pre-defined order.
    # This is important, because team order is otherwise wrong.
    @sprint_id_array = sort { $a < $b } @sprint_id_array;
    for my $sprint_id (@sprint_id_array) {
        my $bugs                   = $original_sprints{$sprint_id};
        my $original_sprint_length = scalar @{$bugs};
        if ($original_sprint_length != $lengths_hash->{$sprint_id}) {
            return "(Sprint " . $sprint_id . " length " . $lengths_hash->{$sprint_id} . ")";
        }
        foreach my $bug (@{$bugs}) {
            my $before_update_team_order = $old_order_hash->{$bug};
            if ($original_list_counter != $before_update_team_order) {
                return "(Bug " . $bug . " original order " . $original_list_counter . " from database " . $before_update_team_order . ")";
            }
            my $before_update_sprint_id = $sprints_hash->{$bug};
            if ($sprint_id != $before_update_sprint_id) {
                return "(Bug " . $bug . " original sprint " . $sprint_id . " from database " . $before_update_sprint_id . ")";
            }
            $original_list_counter = $original_list_counter + 1;
        }
    }
    return "";
}

sub _old_team_order {
    my ($bug_id) = @_;

    my ($item_id, $team_order) = Bugzilla->dbh->selectrow_array('SELECT bug_id, team FROM scrums_bug_order WHERE bug_id = ?', undef, $bug_id);
    if ($item_id) {
        return $team_order;
    }
    return -1;
}

#
# There are at most two sprints in database, that are active.
# One is backlog and one is the most recent sprint.
#
sub _get_sprints_hashes {
    my ($team_id, $sprints_hash, $lengths_hash) = @_;

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
	spr.team_id = ? and
        spr.item_type = 2 or spr.id = 
        (select id from scrums_sprints spr2 where spr2.team_id = ? and spr2.item_type = 1 and not exists 
        (select null from scrums_sprints spr3 where spr3.team_id = ? and spr3.item_type = 1 and spr3.start_date > spr2.start_date))"
                           );
    trick_taint($team_id);
    $sth->execute($team_id, $team_id, $team_id);

    while (my $row = $sth->fetchrow_arrayref) {
        my ($bug_id, $sprint) = @$row;
        $sprints_hash->{$bug_id} = $sprint;
        if (!$lengths_hash->{$sprint}) {
            $lengths_hash->{$sprint} = 1;
        }
        else {
            $lengths_hash->{$sprint} = $lengths_hash->{$sprint} + 1;
        }
    }
}

1;

__END__

=head1 NAME

Bugzilla::Extension::Scrums::Teamorderlib - Scrums function library for setting bug lists in sprint and backlog.


=head1 SYNOPSIS

    use Bugzilla::Extension::Scrums::Teamorderlib;

    Bugzilla::Extension::Scrums::Teamorderlib::update_bug_order_from_json($team_id, $data, $vars);


=head1 DESCRIPTION

Teamorderlib.pm is a library for setting bug lists.

=head1 METHODS

=over

=item C<update_bug_order_from_json($team_id, $data, $vars)>

 Description: Sets bug lists in active sprint and backlog of team from JSON .

 Params:      team_id          - Id of a Bugzilla::Extension::Scrums::Team object.
              data             - JSON-string from Ajax-interface. Contains bug lists of active sprint and backlog.

 Returns:     The vars-hashref is added the following keys:
              errors              - Possible errors (string) to be returned as Ajax return value
              warnings            - Possible warnings (string) to be returned as Ajax return value

=back

=cut

