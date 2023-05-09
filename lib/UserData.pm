#!/usr/bin/perl -w
#
# Copyright (c) 2003-2006 University of Chicago and Fellowship
# for Interpretations of Genomes. All Rights Reserved.
#
# This file is part of the SEED Toolkit.
#
# The SEED Toolkit is free software. You can redistribute
# it and/or modify it under the terms of the SEED Toolkit
# Public License.
#
# You should have received a copy of the SEED Toolkit Public License
# along with this program; if not write to the University of Chicago
# at info@ci.uchicago.edu or the Fellowship for Interpretation of
# Genomes at veronika@thefig.info or download a copy from
# http://www.theseed.org/LICENSE.TXT.
#


package UserData;

    require Exporter;
    @ISA = ('Exporter');
    @EXPORT = qw();
    @EXPORT_OK = qw();

    use strict;
    use Tracer;
    use PageBuilder;

=head1 FIG User Configuration Module

=head2 Introduction

The user data object allows the SEED to determine the privileges and
preferences of SEED users. This is not intended as an ironclad security
system; rather, its goal is to prevent one group stepping on another group's
work and to allow individual users to customize the look and feel of the
SEED.

=head3 Capabilities

Capabilities provide three access levels-- C<RW> (read-write), C<RO> (read-only),
and C<NO> (no access). Capabilities are managed using arbitrary classes of genomes
and subsystems called I<groups>. Groups are stored globally. Each group has a
name and a default access level. The default group is called C<normal> and has
a default access level of C<RW>.

Each user has a list of capabilities, each consisting of a group name and an
access level. A group name / access level pair is called a I<subscription>.
When a user attempts to access a subsystem or genome, we get the genome or
subsystem's group name and ask if the user has a subscription to the group.
If he does, the access level in the subscription is used. If he does not, the
default access level for the group is used.

If the user name is not known, the default user-- C<basic>-- will be used.
Initially, this default user will have no subscriptions, and as a result
will have default access to all genome and subsystem groups; however, if this
is not desirable it can be changed by adding subscriptions to the basic user
record.

=head3 Preferences

Preferences are simple key-value pairs. For each key, there is a single string
value. The key name cannot contain any white space. The keys are treated like
simple unformatted keys; however, it is highly recommened that the colon
character (C<:>) be used to separate the name into a category and a subkey
name. For example, C<genomes:columnList> would indicate the column-list
preference for the B<genomes> category. If the number of keys becomes
large, the category concept will enable us to restructure the data to reduce
the memory footprint.

Every user has his own set of preferences. The default user C<basic> should
have a complete set of preferences; if a preference is not specified for a
particular user, the basic user's value will be used instead.

=head2 Access Objects

This module does not access the actual data. Instead, it accepts as input
an I<access object>. The access object hides the details of data access
from the User Data object so that different data stores can be plugged
in. Currently, the access objects used by most of the SEED are the
B<FIG> and B<SFXlate> objects. FIG uses a combination of flat files and
database tables and supports both reads and updates. The SFXlate object
uses a pure database scheme and is mostly read-only.

#: Constructor UserData->new();

=head2 Public Methods

=head3 new

    my $userData = UserData->new($user, $fig);

Construct the capabilities object for a specified user.

=over 4

=item user

Name of the current user.

=item fig

Access object for retrieving user data.

=back

=cut

sub new {
    # Get the parameters.
    my ($class, $user, $fig) = @_;
    # Get the user's capabilities.
    my $capable = $fig->GetCapabilities($user);
    # Create the userdata object.
    my $retVal = {
                  capable => $capable,
                  newCapable => { },
                  user => $user,
                  preferences => { },
                  newPreferences => { },
                  fig => $fig
                 };
    # Bless and return it.
    bless $retVal, $class;
    return $retVal;
}

=head3 GetCapability

    my $level = $userData->GetCapability($objectID, $objectType);

Get this user's access level for the specified object-- either C<RW> (full access),
C<RO> (read-only), or C<NO> (no access).

=over 4

=item objectID

ID of the relevant object.

=item objectType

Type of the relevant object. This should be the Sprout entity name for the
object type. Currently, only C<Subsystem> and C<Genome> are supported.

=item RETURN

Returns C<RW> if the user has full access, C<RO> if the user has read-only
access, and C<NO> if the user should not have any access to the object.

=back

=cut

sub GetCapability {
    # Get the parameters.
    my ($self, $objectID, $objectType) = @_;
    # Look for the group and default access level of the target object.
    my ($group, $level) = $self->{fig}->GetDefault($objectID, $objectType);
    # If it wasn't found, the group is 'normal' and the access level is RW.
    if (! $group) {
        ($group, $level) = ('normal', 'RW');
    }
    # If this group is in the user's capability hash, we use the result to
    # override the level.
    if (exists $self->{capable}->{$group}) {
        $level = $self->{capable}->{$group};
    }
    # Return the level.
    return $level;
}

=head3 GetPreference

    my $value = $userData->GetPreference($key);

Return the user's preference value for the specified key.

=over 4

=item key

Fully-qualified key for the preference value.

=item RETURN

Returns the preference value for the key. If the user has no explicit preference
value for that key, returns the corresponding value for the default user.

=back

=cut

sub GetPreference {
    # Get the parameters.
    my ($self, $key) = @_;
    # Extract the category name.
    my $category = ParseCategory($key);
    # Insure this category is in memory.
    my $categoryHash = $self->GetCategoryHash($category);
    # Return the value for the specified preference key.
    my $retVal = $categoryHash->{$key};
    return $retVal;
}

=head3 SetCapabilities

    $userData->SetCapabilities(\%groupMap);

Set capabilities for this user. This does not replace all existing capabilities.
Instead, the capabilities specified in the group map are updated or deleted,
and any capabilities not specified are unchanged. Note that the actual changes
are cached in memory, and are not written until the L</SaveChanges> method is
called.

=over 4

=item groupMap

Reference to a hash mapping group names to access levels (C<RW> full access,
C<RO> read-only access, C<NO> no access) or an undefined value if the user
is to have default access to the specified group.

=back

=cut

sub SetCapabilities {
    # Get the parameters.
    my ($self, $groupMap) = @_;
    # Loop through the settings, adding them to the update hash and the actual
    # hash. The update hash is used when we save changes. The actual hash
    # needs to be updated as well so that the new values are retrieved when
    # the client asks for capability data.
    my $accessMap = $self->{capable};
    my $changeMap = $self->{newCapable};
    for my $group (keys %{$groupMap}) {
        $accessMap->{$group} = $groupMap->{$group};
        $changeMap->{$group} = $groupMap->{$group};
    }
}

=head3 SetPreferences

    $userData->SetPreferences(\%preferences);

Set preferences for this user. This does not replace all existing preferences.
Instead, the preferences specified in the map are updated or deleted, and any
preferences not specified are unchanged. Note that the settings are not changed.
Instead, the changes are cached in memory until the L</SaveChanges> method is
called.

=over 4

=item preferences

Reference to a hash mapping key names to preference values. Mapping a key
name to an undefined value indicates that the default preference value
should be used.

=back

=cut

sub SetPreferences {
    # Get the parameters.
    my ($self, $preferences) = @_;
    # Loop through the settings. Each one is added to the main hash and then
    # cached in the update hash.
    my $changeMap = $self->{newPreferences};
    for my $key (keys %{$preferences}) {
        # Extract the category name from the key.
        my $category = ParseCategory($key);
        # Insure we have the category in memory.
        my $hash = $self->GetCategoryHash($category);
        # Add the new value to the category hash.
        $hash->{$key} = $preferences->{$key};
        # Add it to the update hash.
        $changeMap->{$key} = $preferences->{$key};
    }
}

=head3 SetDefault

    $userData->SetDefault($objectID, $objectType, $group, $level);

Set the group and default access level for the specified object. This update
takes place immediately.

=over 4

=item objectID

ID of the object whose access level and group are to be set.

=item objectType

Type of the relevant object. This should be expressed as a Sprout entity name.
Currently, only C<Genome> and C<Subsystem> are supported.

=item group

Name of the group to which the object will belong. A user's access level for
this group will override the default access level.

=item level

Default access level. This is the access level used for user's who do not have
an explicit capability specified for the object's group.

=back

=cut

sub SetDefault {
    # Get the parameters.
    my ($self, $objectID, $objectType, $group, $level) = @_;
    # Call the access method.
    $self->{fig}->SetDefault($objectID, $objectType, $group, $level);
}

=head3 SaveChanges

    $userData->SaveChanges();

Store accumulated preference and capability changes.

=cut

sub SaveChanges {
    # Get the parameters.
    my ($self) = @_;
    # Check for capability updates.
    my $capabilityUpdates = $self->{newCapable};
    if (keys %{$capabilityUpdates}) {
        $self->{fig}->SetCapabilities($self->{user}, $capabilityUpdates);
    }
    # Check for preference updates.
    my $preferenceUpdates = $self->{newPreferences};
    if (keys %{$preferenceUpdates}) {
        $self->{fig}->SetPreferences($self->{user}, $preferenceUpdates);
    }
}

=head3 ParseCategory

    my $category = UserData::ParseCategory($key);

Return the category name from the specified preference key. If no category is
specified, an error will occur.

=over 4

=item key

Preference key, which consists of alphanumeric characters with colons separating
the sections.

=item RETURN

Returns the category name from the specified key.

=back

=cut

sub ParseCategory {
    # Get the parameters.
    my ($key) = @_;
    # Declare the return variable.
    my $retVal;
    # Try to parse out the category.
    if ($key =~ /([^:]+):/) {
        # Return the category.
        $retVal = $1;
    } else {
        # Here we have no category, so it's an error.
        Confess("No category specified on preference key \"$key\".");
    }
    return $retVal;
}

=head3 GetCategoryHash

    my $categoryHash = $self->GetCategoryHash($category);

Return the hash for the specified category. If it is not in memory, it
will be read in.

=over 4

=item key

Preference key, which consists of alphanumeric characters with colons separating
the sections.

=item RETURN

Returns the category name from the specified key.

=back

=cut

sub GetCategoryHash {
    # Get the parameters.
    my ($self, $category) = @_;
    # Declare the return variable.
    my $retVal;
    # Check to see if we have preferences for this category. If not, we need
    # to read them in.
    if (! exists $self->{preferences}->{$category}) {
        # Get the default preferences if this is not the default user.
        my $defaults = {};
        if ($self->{user} ne 'basic') {
            $defaults = $self->{fig}->GetPreferences('basic', $category);
        }
        # Get the user's preferences and merge them in.
        my $overrides = $self->{fig}->GetPreferences($self->{user}, $category);
        for my $key0 (%{$overrides}) {
            $defaults->{$key0} = $overrides->{$key0};
        }
        # Add the new hash to the preferences hash.
        $self->{preferences}->{$category} = $defaults;
        # Return it.
        $retVal = $defaults;
    } else {
        # Here the hash is already in memory.
        $retVal = $self->{preferences}->{$category};
    }
    # Return the category hash.
    return $retVal;
}

=head2 Access Object Methods

The following methods must be implemented by the access object (e.g. I<$fig>) passed
to the constructor.

=head3 GetDefault

    my ($group, $level) = $fig->GetDefault($objectID, $objectType);

Return the group name and default access level for the specified object.

=over 4

=item objectID

ID of the object whose capabilities data is desired.

=item objectType

Type of the object whose capabilities data is desired. This should be expressed
as a Sprout entity name. Currently, the only types supported are C<Genome>
and C<Subsystem>.

=item RETURN

Returns a two-element list. The first element is the name of the group
to witch the object belongs; the second is the default access level
(C<RW>, C<RO>, or C<NO>). If the object is not found, an empty list
should be returned.

=back

=head3 GetPreferences

    my $preferences = $fig->GetPreferences($userID, $category);

Return a map of preference keys to values for the specified user in the
specified category.

=over 4

=item userID

ID of the user whose preferences are desired.

=item category (optional)

Name of the category whose preferences are desired. If omitted, all
preferences should be returned.

=item RETURN

Returns a reference to a hash mapping each preference key to a value. The
keys are fully-qualified; in other words, the category name is included.
It is acceptable for the hash to contain key-value pairs outside the
category. In other words, if it's easier for you to read the entire
preference set into memory, you can return that one set every time
this method is called without worrying about the extra keys.

=back

=head3 GetCapabilities

    my $level = $fig->GetCapabilities($userID);

Return a map of group names to access levels (C<RW>, C<RO>, or C<NO>) for the
specified user.

=over 4

=item userID

ID of the user whose access level is desired.

=item RETURN

Returns a reference to a hash mapping group names to the user's access level
for that group.

=back

=head3 AllowsUpdates

    my $flag = $fig->AllowsUpdates();

Return TRUE if this access object supports updates, else FALSE. If the access object
does not support updates, none of the B<SetXXXX> methods will be called.

=head3 SetDefault

    $fig->SetDefault($objectID, $objectType, $group, $level);

Set the group and default access level for the specified object.

=over 4

=item objectID

ID of the object whose access level and group are to be set.

=item objectType

Type of the relevant object. This should be expressed as a Sprout entity name.
Currently, only C<Genome> and C<Subsystem> are supported.

=item group

Name of the group to which the object will belong. A user's access level for
this group will override the default access level.

=item level

Default access level. This is the access level used for user's who do not have
an explicit capability specified for the object's group.

=back

=head3 SetCapabilities

    $fig->SetCapabilities($userID, \%groupLevelMap);

Set the access levels by the specified user for the specified groups.

=over 4

=item userID

ID of the user whose capabilities are to be updated.

=item groupLevelMap

Reference to a hash that maps group names to access levels. The legal
access levels are C<RW> (read-write), C<RO> (read-only), and C<NO> (no
access). An undefined value for the access level indicates the default
level should be used for that group. The map will not replace all of
the user's capability date; instead, it overrides existing data, with
the undefined values indicating the specified group should be deleted
from the list.

=back

=head3 SetPreferences

    $fig->SetPreferences($userID, \%preferenceMap);

Set the preferences for the specified user.

=over 4

=item userID

ID of the user whose preferences are to be udpated.

=item preferenceMap

Reference to a hash that maps each preference key to its value. The
keys should be fully-qualified (that is, they should include the
category name). A preference key mapped to an undefined value will
use the default preference value for that key. The map will not
replace all of the user's preference data; instead, it overrides
existing data, with the undefined values indicating the specified
preference should be deleted from the list.

=back

=head3 CleanupUserData

    $fig->CleanupUserData();

Release any data being held in memory for use by the UserData object.

=head2 Fields

The user data object contains the following fields.

=over 4

=item capable

Reference to a hash containing all the user's capability data.

=item preferences

Reference to a hash of hashes. The key of the large hash is the preference
category, and the value is a small hash mapping preferences from that
category to values.

=item userID

Current user's ID.

=item fig

Fig-like object for accessing the data.

=item newCapable

Hash containing updated capabilities.

=item newPreferences

Hash containing updated preferences.

=back

=cut

1;
