package Filesys::Virtual::Categories;

use strict;
use warnings;

use Foswiki::Func                          ();
use Foswiki::Plugins::ClassificationPlugin ();
use Filesys::Virtual::Attachments          ();
our @ISA = ('Filesys::Virtual::Attachments');

use Data::Dump qw(dump);
use constant NOCAT => '00.uncategorized';

sub new {
    my $class = shift;
    my $args  = shift;

    my $this = bless( $class->SUPER::new($args), $class );

    $this->{hideEmptyCategories} =
      $Foswiki::cfg{Plugins}{FilesysVirtualPlugin}{HideEmptyCategories}
      || 0;

    return $this;
}

# Break a resource into its component parts, web, category, topic, attachment.
# The return value is an array which may have up to 3 entries:
# [0] is always the full web path name
# [1] is always the topic name with no suffix
# [2] is the attachment name
# [3] is the category
# if the array is empty, that indicates the root (/)
sub _parseResource {
    my ( $this, $resource ) = @_;

    if ( defined $this->{location} && $resource =~ s/^$this->{location}// ) {

        # Absolute path; must be, cos it has a location
    }
    elsif ( $resource !~ /^\// ) {

        # relative path
        $resource = $this->{path} . '/' . $resource;
    }
    $resource =~ s/\/\/+/\//g;    # normalise // -> /
    $resource =~ s/^\/+//;        # remove leading /

    # Resolve the path into it's components
    my @path;
    foreach ( split( /\//, $resource ) ) {
        if ( $_ eq '..' ) {
            if ($#path) {
                pop(@path);
            }
        }
        elsif ( $_ eq '.' ) {
            next;
        }
        elsif ( $_ eq '~' ) {
            @path = ( $Foswiki::cfg{UsersWebName} );
        }
        else {
            push( @path, $_ );
        }
    }

    # strip off hidden attribute from filename
    @path = map { $_ =~ s/^\.//; $_ } @path if $this->{hideEmptyAttachmentDirs};

    # rebuild normalized resource
    $resource = join( "/", @path );

    # get web part
    my $web = '';
    while (@path) {
        last if $web && Foswiki::Func::topicExists( $web, $path[0] );
        if ( Foswiki::Func::webExists($web) ) {
            my $hierarchy =
              Foswiki::Plugins::ClassificationPlugin::getHierarchy($web);
            last if $path[0] eq NOCAT || $hierarchy->getCategory( $path[0] );
        }
        $web .= ( $web ? '/' : '' ) . shift(@path);
    }

    my %info = (
        type     => 'R',
        web      => $web,
        resource => $resource,
    );

    # get category part
    my $catPath = '';
    if ( Foswiki::Func::webExists($web) ) {
        my $cat = '';
        my $hierarchy =
          Foswiki::Plugins::ClassificationPlugin::getHierarchy($web);
        while ( @path
            && ( $path[0] eq NOCAT || $hierarchy->getCategory( $path[0] ) ) )
        {
            $cat = shift(@path);
            $catPath = ( $catPath ? '/' : '' ) . $cat;
        }
        $info{category} = $cat if $cat;
    }

    # get topic part
    $info{topic} = shift(@path) if Foswiki::Func::topicExists( $web, $path[0] );

    # get attachment part
    $info{attachment} = shift(@path);

    # anything else is an error
    return undef if scalar(@path);

    # derive type from found resources and rebuild path
    @path = ();
    if ( $info{web} ) {
        push @path, $info{web};

        if ( $info{category} ) {
            push @path, $catPath;
            $info{type} = 'C';
        }
        else {
            $info{type} = 'W';
        }

        if ( $info{topic} ) {
            push @path, $info{topic};
            $info{type} = 'D';
        }

        if ( $info{attachment} ) {
            push @path, $info{attachment};
            $info{type} = 'A';
        }
    }

    # init topic for compatibility with upper level
    $info{topic} ||= $info{category};

    $info{path} = join( "/", @path );

    #print STDERR dump(\%info)."\n";

    return \%info;
}

sub _C_chdir {
    my ( $this, $info ) = @_;

    if ( Foswiki::Func::topicExists( $info->{web}, $info->{topic} ) ) {
        $this->{path} = $info->{path};
        return $this->{path};
    }
    return undef;
}

sub _W_list {
    my ( $this, $info ) = @_;

    return $this->_fail( POSIX::ENOENT, $info )
      unless Foswiki::Func::webExists( $info->{web} );
    return $this->_fail( POSIX::EACCES, $info )
      unless $this->_haveAccess( 'VIEW', $info->{web} );

    my @list = ();

    foreach my $sweb ( Foswiki::Func::getListOfWebs('user,public') ) {
        next if $sweb eq $info->{web};
        next unless $sweb =~ s/^$info->{web}\/+//;
        next if $sweb =~ m#/#;
        push( @list, $sweb );
    }

    my $hierarchy =
      Foswiki::Plugins::ClassificationPlugin::getHierarchy( $info->{web} );

    # add top category
    my $cat = $hierarchy->getCategory("TopCategory");

    if ( $this->{hideEmptyCategories} ) {
        foreach my $child ( $cat->getChildren() ) {
            my $catName = $child->{name};
            next if $catName eq 'BottomCategory';
            $catName = '.' . $catName unless $child->countTopics();
            push @list, $catName;
        }
    }
    else {
        push @list,
          grep { !/^BottomCategory$/ } map { $_->{name} } $cat->getChildren();
    }

    # add no category
    push @list, NOCAT;

    push @list, '.';
    push @list, '..';

    return \@list;
}

sub _C_list {
    my ( $this, $info ) = @_;

    return $this->_fail( POSIX::ENOENT, $info )
      unless Foswiki::Func::webExists( $info->{web} );
    return $this->_fail( POSIX::EACCES, $info )
      unless $this->_haveAccess( 'VIEW', $info->{web} );

    my @list = ();

    my $hierarchy =
      Foswiki::Plugins::ClassificationPlugin::getHierarchy( $info->{web} );
    my $cat;

    if ( $info->{category} eq NOCAT ) {
        $cat = $hierarchy->getCategory('TopCategory');
    }
    else {
        $cat = $hierarchy->getCategory( $info->{category} );
        return $this->_fail( POSIX::ENOENT, $info ) unless $cat;

        # add child categories

        if ( $this->{hideEmptyCategories} ) {
            foreach my $child ( $cat->getChildren() ) {
                my $catName = $child->{name};
                next if $catName eq 'BottomCategory';
                $catName = '.' . $catName unless $child->countTopics();
                push @list, $catName;
            }
        }
        else {
            push @list,
              grep { !/^BottomCategory$/ }
              map  { $_->{name} } $cat->getChildren();
        }

        # add attachments to this category topic
        push @list,
          grep { !/$this->{excludeAttachments}/ }
          Foswiki::Func::getAttachmentList( $info->{web}, $info->{category} );
    }

    # add topics in that category
    if ( $this->{hideEmptyAttachmentDirs} ) {
        foreach my $topic ( $cat->getTopics ) {
            $topic = '.' . $topic
              unless $this->_hasAttachments( $info->{web}, $topic );
            push @list, $topic;
        }
    }
    else {
        push @list, $cat->getTopics();
    }

    push @list, '.';
    push @list, '..';

    return \@list;
}

# deny - better don't delete categories using webdav for now
sub _C_delete {
    return shift->_fail( POSIX::EPERM, @_ );
}

# deny - can't mkdir categories
sub _C_mkdir {
    return shift->_fail( POSIX::EPERM, @_ );
}

sub _C_open_read {
    return shift->_fail( POSIX::EPERM, @_ );
}

sub _C_open_write {
    return shift->_fail( POSIX::EPERM, @_ );
}

# TODO
sub _C_rename {
    return shift->_fail( POSIX::EPERM, @_ );
}

# TODO
sub _C_rmdir {
    return shift->_fail( POSIX::EPERM, @_ );
}

sub _C_stat {
    my ( $this, $info ) = @_;

    #print STDERR "called _C_stat($info->{category})\n";

    my $hierarchy =
      Foswiki::Plugins::ClassificationPlugin::getHierarchy( $info->{web} );
    my $catName =
      $info->{category} eq NOCAT ? 'TopCategory' : $info->{category};
    my $cat = $hierarchy->getCategory($catName);

    return () unless $cat;

    my $file = "$Foswiki::cfg{DataDir}/$cat->{origWeb}/$catName.txt";
    my @stat = CORE::stat($file);
    $stat[2] = $this->_getMode( $cat->{origWeb}, $catName );
    $stat[2] = ( $stat[2] & ~(00222) )
      if $cat->{origWeb} ne $info->{web} || $info->{category} eq NOCAT;

    #printf STDERR "mode=%#o\n", $stat[2];

    return @stat;
}

sub _C_test {
    my ( $this, $info, $type ) = @_;

    #print STDERR "called _C_test($info->{category}, $type)\n";

    return $this->_fail( POSIX::ENOENT, $info )
      unless Foswiki::Func::webExists( $info->{web} );
    return $this->_fail( POSIX::EACCES, $info )
      unless $this->_haveAccess( 'VIEW', $info->{web} );

    my $hierarchy =
      Foswiki::Plugins::ClassificationPlugin::getHierarchy( $info->{web} );
    my $catName =
      $info->{category} eq NOCAT ? 'TopCategory' : $info->{category};
    my $cat = $hierarchy->getCategory($catName);

    return ( $cat ? 1 : 0 ) if $type eq 'e' || $type eq 'd';
    return (
        $cat ? $this->_haveAccess( 'VIEW', $cat->{origWeb}, $catName ) : 0 )
      if $type =~ /r/i;
    return ( $cat ? ( $cat->{origWeb} eq $info->{web} ? 1 : 0 ) : 0 )
      if $type =~ /w/i;

    return 1 if $type =~ /x/i;
    return 1 if $type =~ /o/i;

    return 0 if $type eq 'f';
    return 0 if $type eq 'T';
    return 0 if $type eq 'B';

    return ( $cat ? scalar( $cat->getChildren ) == 0 : 0 ) if $type eq 'z';
    return ( $cat ? scalar( $cat->getChildren )      : 0 ) if $type eq 's';

    # missing: l
    # off: p, S, b, t, u, g, k, M

    my $file = "$Foswiki::cfg{PubDir}/$cat->{origWeb}/$catName.txt";

    return eval "-$type $file";
}

1;
