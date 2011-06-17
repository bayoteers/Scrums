#!/usr/bin/perl

package Bugzilla::Extension::Scrums::LoadTestData;

use strict;

use Data::Dumper;
use lib qw(. lib);

use Bugzilla;

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Group;
use Bugzilla::User;

use Bugzilla::Util qw(trick_taint);

use Bugzilla::Extension::Scrums::Team;

use base qw(Exporter);
use Bugzilla::Error;

our @EXPORT = qw(
  load_test_data
  );

use constant TEAMCOUNT => 50;
use constant TEAMSIZE  => 10;

use vars qw(%data);

sub load_test_data($) {
    my ($vars) = @_;

    _drop_existing_data();

    for my $i_team (1 .. TEAMCOUNT) {
        # Create a team based on an existing product.

        my ($product_id, $name) = _get_random_product();
        my $owner        = _get_random_user();
        my $scrum_master = _get_random_user();

        $vars->{'output'} .= "<p>Loaded Team $name, $owner, $scrum_master</p>";

        my $team = Bugzilla::Extension::Scrums::Team->create({ name => $name, owner => $owner, scrum_master => $scrum_master });
        _create_backlog($team->id);

        # Add members to this team.

        for my $i_member (1 .. TEAMSIZE) {
            my $member = _get_random_user();
            $vars->{'output'} .= "<p>Added Member $member to Team $i_team</p>";

            $team->set_member($member);
        }

        # Get the components in this product and add them to this team's responsibilities.
        my $product = new Bugzilla::Product($product_id);
        foreach my $component (@{ $product->components }) {
            $team->set_component($component->id);
        }
    }

    $vars->{'output'} .= '<p>Loaded</p>';
}

sub _create_backlog($) {
    my ($team_id) = @_;

    my $sprint = Bugzilla::Extension::Scrums::Sprint->create(
                                                         {
                                                           team_id          => $team_id,
                                                           status           => "NEW",
                                                           item_type        => 2,
                                                           name             => "Product Backlog",
                                                           nominal_schedule => "2000-01-01",
                                                           description => "This is automatically generated static 'sprint' for the purpose of product backlog",
                                                           is_active   => 1
                                                         }
    );

}

sub _drop_existing_data() {
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction();

    Bugzilla->dbh->do('delete from scrums_bug_order',            undef);
    Bugzilla->dbh->do('delete from scrums_componentteam',        undef);
    Bugzilla->dbh->do('delete from scrums_flagtype_release_map', undef);
    Bugzilla->dbh->do('delete from scrums_releases',             undef);
    Bugzilla->dbh->do('delete from scrums_sprints',              undef);
    Bugzilla->dbh->do('delete from scrums_team',                 undef);
    Bugzilla->dbh->do('delete from scrums_teammember',           undef);
    Bugzilla->dbh->do('delete from scrums_sprint_bug_map',       undef);

    $dbh->bz_commit_transaction();
}

sub _get_random_user() {
    my $dbh = Bugzilla->dbh;

    my $user_id;

    do {
        my $query = "SELECT userid FROM profiles ORDER BY rand() limit 1;";
        $user_id = Bugzilla->dbh->selectrow_array($query);

    } until !$data{'user'}{$user_id};

    $data{'user'}{$user_id} = 1;

    return $user_id;
}

sub _get_random_product() {
    my $dbh = Bugzilla->dbh;

    my ($id, $name);

    do {
        my $query = "SELECT id,name FROM products ORDER BY rand() limit 1;";
        ($id, $name) = Bugzilla->dbh->selectrow_array($query);

    } until !$data{'product'}{$id};

    $data{'product'}{$id} = 1;

    return ($id, $name);
}

sub _get_bugs_in_product() {
    my @bug_ids;

    return @bug_ids;
}

sub _assign_component_to_team($$) {
    my ($component, $team_id) = @_;

    return;
}

sub _put_bug_in_sprint($$) {
    my ($bug_id, $sprint) = @_;

    return;
}

sub _order_bug_in_sprint($$) {
    my ($bug_id, $team_id) = @_;

    return;
}

1;
