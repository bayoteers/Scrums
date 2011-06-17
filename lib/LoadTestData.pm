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

use Date::Calc qw(Week_Number Today Add_Delta_Days);

our @EXPORT = qw(
  load_test_data
  );

use constant TEAMCOUNT   => 7;
use constant TEAMSIZE    => 7;
use constant SPRINTCOUNT => 7;
use constant SPRINTLENGTH => 14;

use vars qw(%data);

sub load_test_data($) {
    my ($vars) = @_;

    # Drop all existing data.
    _drop_existing_data();

    for my $i_team (1 .. TEAMCOUNT) {
        # Create a team based on an existing product.

        my ($product_id, $name) = _get_random_product();
        my $owner        = _get_random_user();
        my $scrum_master = _get_random_user();

        $vars->{'output'} .= "<p><strong>Loading Team $name</strong><br />";

        my $team = Bugzilla::Extension::Scrums::Team->create({ name => $name, owner => $owner, scrum_master => $scrum_master });
        _create_backlog($team->id);

        # Add members to this team.

        for my $i_member (1 .. TEAMSIZE) {
            my $member = _get_random_user();
            $vars->{'output'} .= "Adding Member $member<br />";

            $team->set_member($member);
        }

        # Get the components in this product and add them to this team's responsibilities.

        my $product = new Bugzilla::Product($product_id);
        foreach my $component (@{ $product->components }) {
            $team->set_component($component->id);
        }

        # Create sprints counting back two weeks from now.
        
        my ($s_year,$s_month,$s_day) = Today(time());
        ($s_year,$s_month,$s_day) = Add_Delta_Days($s_year, $s_month, $s_day, -((SPRINTCOUNT*SPRINTLENGTH)/2));

        for my $i_sprint (1 .. SPRINTCOUNT) {
             my ($year, $month, $day) = Add_Delta_Days($s_year, $s_month, $s_day, 14);
             
             my $s_week_number = Week_Number($s_year,$s_month,$s_day);
             my $e_week_number = Week_Number($year,$month,$day);
             
             my $is_active = 1;
             
             $vars->{'output'} .= "Creating Sprint $i_sprint Week $s_week_number -> $e_week_number<br />";

             _create_sprint($team->id,"NEW", 1, "Sprint WK $s_week_number-$e_week_number", "", "Sprint for Week $s_week_number to Week $e_week_number", $is_active);
             
             ($s_year, $s_month, $s_day) = ($year, $month, $day);
        }
        
        $vars->{'output'} .= "</p>";
    }

    $vars->{'output'} .= '<p>Loaded Complete</p>';
}

sub _create_backlog($) {
    my ($team_id) = @_;
    
    # Create a backlog, which is actually just a sprint in thin disguise.

    my ($backlog) = _create_sprint($team_id, "NEW", 2, "Product Backlog", "2000-01-01", "Automatically generated sprint that represents the Product Backlog", 1);
    
    return $backlog;
}

sub _create_sprint(@) {
    my ($team_id, $status, $item_type, $name, $nominal_schedule, $description, $is_active) = @_;
    
    # Create a sprint.

    my $sprint = Bugzilla::Extension::Scrums::Sprint->create(
                                                             {
                                                               team_id          => $team_id,
                                                               status           => $status,
                                                               item_type        => $item_type,
                                                               name             => $name,
                                                               nominal_schedule => $nominal_schedule,
                                                               description      => $description,
                                                               is_active        => $is_active
                                                             }
                                                            );

    return $sprint;
}

sub _drop_existing_data() {
    my $dbh = Bugzilla->dbh;
    
    # Drop all existing data in scrums_* tables.

    my @tables = (
                  'scrums_bug_order', 'scrums_componentteam', 'scrums_flagtype_release_map', 'scrums_releases',
                  'scrums_sprints',   'scrums_team',          'scrums_teammember',           'scrums_sprint_bug_map'
                 );

    $dbh->bz_start_transaction();

    foreach my $table (@tables) {
        Bugzilla->dbh->do("delete from $table");
    }

    $dbh->bz_commit_transaction();
}

sub _get_random_user() {
    my $dbh = Bugzilla->dbh;
    
    # Get random user, that hasn't been previously used during this run.

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
    
    # Get random product, that hasn't been previously used during this run.

    my ($id, $name);

    do {
        my $query = "SELECT id,name FROM products ORDER BY rand() limit 1;";
        ($id, $name) = Bugzilla->dbh->selectrow_array($query);
        
    } until !$data{'product'}{$id};

    $data{'product'}{$id} = 1;

    return ($id, $name);
}

1;
