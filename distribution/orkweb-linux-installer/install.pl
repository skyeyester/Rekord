#!/usr/bin/perl

## Usage: install.pl <arguments> where <arguments> can be:
##   --nomysql 
##   --nojava 
##   --notomcat
##   --nooreka
##   --silent
##
## Defaults are:
##    Java path  :  /opt/java/jre1.7.0_02
##    Tomcat path:  /opt/tomcat7
##    MySQL      :  username=root, password=, database name=oreka
##
##
## By default, Tomcat will be installed as non-root, group/under tomcat/tomcat 
##
use IO::Handle;
use POSIX 'strftime';

$verifyMySQLInstalled = 1;
$installJava   = 1;
$installTomcat = 1;
$installOreka  = 1;
$installSilent = 0;

foreach (@ARGV) {
  if ($_ eq "--nomysql") {
     $verifyMySQLInstalled = 0;      
     print "MySQL will not be installed...\n";
  } elsif ($_ eq "--nojava") {
     $installJava = 0;      
     print "Java will not be installed...\n";
  } elsif ($_ eq "--notomcat") {
     $installTomcat = 0;      
     print "Tomcat will not be installed...\n";
  } elsif ($_ eq "--nooreka") {
     $installOreka = 0;      
     print "OrkWeb will not be installed...\n";
  } elsif ($_ eq "--silent") {
     $installSilent = 1;      
     $verifyMySQLInstalled = 0;
     print "Silent installation: no prompts will be used and all defaults will be applied.\n";
     print "Note: do not forget to ensure that MySQL is installed and running.\n";
  }
}


use File::Copy;
#use DBI;
#use LWP::Simple;
#use Net::FTP;

$tomcatInstalledAsService = 0;
$tomcatInstalledAsRoot = 0;
$mysqlVerified  = 0;
$tomcatVerified = 0;
$javaVerified   = 0;

$catalinaHome = "";
$defaultCatalinaHome = "/opt/tomcat7";
$javaHome = "";
$defaultJavaHome = "/opt/java/jre1.7.0_02";
$orkwebConfigDir = "/etc/orkweb/";
$audioDir = "/var/log/orkaudio/audio";
$loggingDir = "/var/log/orkweb";
  
$tomcatUser = "tomcat";
$tomcatGroup = "tomcat";
$tomcatUserHome = "/home/tomcat";
$catalinaFile = "catalina.sh"; 

$mysqlCommandlineLocation = "";
$which="which";
$wget="/usr/bin/wget";
$unzip="/usr/bin/unzip";
$gunzip="/bin/gunzip";
$tar="/bin/tar";
$chown="/bin/chown";
$groupadd="/usr/sbin/groupadd";
$useradd="/usr/sbin/useradd";
$whichExists = 0;


# Default OS to CentOS
$operatingSystem="centos";
$typeOS=32;
&getOperatingSystem();

print "\n**** Welcome to the Oreka Web User Interface installer by OrecX LLC ****\n";

## Verifying that wget and unzip are found
# print "\nSearching for required system binaries (wget, unzip, ...)\n";
$which = &verifyTools("which");
if ($which ne '') { $whichExists=1 };
$wget = &verifyTools("wget");
$unzip = &verifyTools("unzip");
$gunzip = &verifyTools("gunzip");
$tar = &verifyTools("tar");
$chown = &verifyTools("chown");
$groupadd = &verifyTools("groupadd");
$useradd = &verifyTools("useradd");

## Verify MySQL existence
if ($verifyMySQLInstalled == 1) {
  print "\nVerifying MySQL database installation...\n";
  &verifyMysqlServerInstalled();

  ## Request basic data for database connection
  print "\nClick enter to accept defaults...\n";

  &obtainMysqlLocation();
  &getHostName();
  &getDatabase();
  &getUser();
  &getPasswords();

  ## Create database
  &createDatabase($mysqlDatabase);

  ## Check MySQL
  &verifyDatabase();
  $mysqlVerified = 1;
}

if ($installJava == 1) {
  ## Check for Java, need >= JRE 1.6.  Install it if user agrees.
  &installJava();
}

if ($installTomcat == 1) {

  ## Check that Java is installed before installing Tomcat
  if ($javaVerified == 0) {
    &verifyJavaExistence();
  }

  ## Install tomcat if user chooses to, otherwise, Tomcat 4 or greater is expected. 
  &verifyTomcat();
} 

if ($installOreka == 1) {

  ## Get database params if not already obtained (and if not in silent mode)
  if ($verifyMySQLInstalled == 1 && $mysqlVerified == 0 && $installSilent == 0) {
    ## Request basic data for database connection
    print "\nClick enter to accept defaults...\n";

    &obtainMysqlLocation();
    &getHostName();
    &getDatabase();
    &getUser();
    &getPasswords();
  }

  ## Ensure that tomcat path was previously set
  if ($tomcatVerified == 0) { 
    ## Check that Java is installed
    if ($javaVerified == 0) {
      &verifyJavaExistence();
    }
    &verifyTomcatExistence();
  }

  ## Create the config files in /etc/orkweb and modify them depending on user input
  &updateOrkwebConfig();

  ## Modify database.hbm.xml
  if ($verifyMySQLInstalled == 1) {
  &updateHibernateConfig();
  }   

  ## Modify logging.properties
  &updateLoggingConfig();

  ## Deploy orkweb and orktrack to tomcat, and modify their web.xml files
  &deployWebAppsToTomcat();
  &updateAppWebXML();

  ## Create default audio file storage directory
  $cmd = "mkdir -p ".$audioDir;
  $pid = `$cmd`;

}

## Make sure Tomcat runs in desired mode (tomcat or root) 
if ($installTomcat == 1 || $installOreka == 1) {
  &configureTomcatRunMode();
}

if($tomcatInstall == 1) {
  print "\n**** The installation has been completed successfully! ****\n\n";
  print "In order to run the Oreka applications manually, you can run:\n";
  print "# /etc/init.d/tomcat start\n";
  if($tomcatInstalledAsService == 1)
  {
	print "In order to start the Oreka applications as a service, you can run:\n";
	print "# service tomcat start\n";
  }
}
print "\nIf you need any help, please contact support\@orecx.com\n\n";

################################## SUBROUTINES ######################################

## Read into /etc/*release file for OS version, and get OS type (32 or 64bit)
sub getOperatingSystem() {

  $os = `cat /etc/*release`; 

  if ($os =~ m/centos/i) {
    $operatingSystem = "centos";
  } elsif ($os =~ m/suse/i) {
    $operatingSystem = "suse";
  } else {
    $operatingSystem = "unknown";
  }
  
  ## Is OS 32-bit or 64-bit?
  $type = `/usr/bin/getconf LONG_BIT`;
  if ($type==64) {
    $typeOS = 64;
    print "64-bit OS detected...\n";
  }
}

## Install utility passed as param using yum
sub yumInstall {

  $ret_val = "";   

  if ($_[0] ne '') {

    ## Find yum 
    $yumExists = 0;
    
    if ($whichExists == 1) {
       $yum = `$which yum`;
       if ($yum ne '') {$yumExists = 1} 
    } else {
        if (-e "/usr/bin/yum"){$yumExists = 1}
        elsif (-e "/bin/yum") {$yumExists = 1}
        elsif (-e "/usr/sbin/yum") {$yumExists = 1}
    }
    
    ## If no yum found exit.    
    if ($yumExists == 0){

       die "\nThe yum package management system is missing. Is this a redhat based derivative Linux system ?\nExiting ...";

    } else {
       
       $resp = '';
       if ($installSilent == 0) {
           do {          
             print "Would you like me to try to install it for you (y/n)?  ";
             $resp= <STDIN>;
             chop $resp;
           } while ($resp ne 'y' && $resp ne 'n');          
       }
        
       if ($resp eq 'y' || $installSilent == 1) {
         print "\nInstalling $_[0]: yum install $_[0]...\n\n";
         if ($installSilent == 1) {
            system("yum -q install $_[0]");
         } else {
            system("yum install $_[0]");
         }   
         if ($whichExists == 1) {        
             $ret_val = `$which $_[0]`;
         } else {
            if (-e "/usr/bin/$_[0]"){$ret_val = "/usr/bin/$_[0]";}
            elsif (-e "/bin/$_[0]") {$ret_val = "/bin/$_[0]";}
            elsif (-e "/usr/sbin/$_[0]") {$ret_val = "/usr/sbin/$_[0]";}
         }
         
         if ($ret_val eq '') {
            print "\nWARNING: Installation of $_[0] failed!\n\n";
         }
       } 
    }
  }
  print "\n";
  return $ret_val;
}

## Verify if tool passed as param is installed (e.g. wget, unzip, ...)
sub verifyTools {
  
  if ($whichExists == 0) {

      if (-e "/usr/bin/$_[0]") {
        $cmd = "/usr/bin/$_[0]";
      } elsif (-e "/bin/$_[0]") {
        $cmd = "/bin/$_[0]";
      } elsif (-e "/usr/sbin/$_[0]") {
        $cmd = "/usr/sbin/$_[0]";
      } else {
        $cmd = "";
      } 
      
  } else {  
    $cmd = `$which $_[0]`;
  }   

  $errorPrompt = "";
  $retval = "";
  
  ## If binary not found, first attempt to install it 
  if ($cmd eq '') { 
    print "'$_[0]' was not found.\n";
    $cmd = &yumInstall($_[0]);
  }

  if ($cmd eq '') {
    
    if ($_[0] eq 'which') {

      print "WARN: 'which' not found...will try to do without it.\n";
    
    } elsif ($_[0] eq 'wget') {
      
      $errorPrompt = "'$_[0]' is required to install Java and Tomcat.  If Java and Tomcat are already installed, you may continue.\n" .
                     "Otherwise, exit this installer and install '$_[0]' first.\n" .
                     "Would you like to continue (y/n)?  ";

    } elsif ($_[0] eq 'unzip') {
      die "'$_[0]' is required to install orkweb and orktrack.  Please install '$_[0]' before proceeding.\n" . 
          "\n\nNo installation was performed. Exiting installer.\n";
      
    } elsif ($_[0] eq 'gunzip') {
      die "'$_[0]' is required to install java.  Please install '$_[0]' before proceeding.\n" . 
          "\n\nNo installation was performed. Exiting installer.\n";
      
    } elsif ($_[0] eq 'tar') {
      die "'$_[0]' is required to install java.  Please install '$_[0]' before proceeding.\n" . 
          "\n\nNo installation was performed. Exiting installer.\n";
      
    } else {
      if ($installSilent == 0) {
        $errorPrompt = "\n'$_[0]' was not found.  Would you like to continue (y/n)?  \n";
      } else {
        $errorPrompt = "\nWARNNIG: *** '$_[0]' was not found.  Installation will proceed, but may fail later!"; 
      }  
    }

    if ($installSilent == 0 && $errorPrompt != "") {
       do {          
         print $errorPrompt;
         $response= <STDIN>;
         chop $response;
       } while ($response ne 'y' && $response ne 'n');          

       if ($response eq 'n'){
         die "\n\nNo installation was performed. Exiting installer.\n";
       } else {
         print "\n";
       }	
    } 
    
  } else {
      $retval = $cmd;
      $retval =~ s/\n//;
      #print "Found '$_[0]' command: $retval \n";
  }
  
  return $retval;
}

sub obtainMysqlLocation {
	my @envPathList, $userResponse;

	@envPathList = split(/:/, $ENV{PATH});
	foreach (@envPathList) {
		if(!length($mysqlCommandlineLocation)) {
			$mysqlCommandlineLocation = $_."/mysql";
			if(!(-e $mysqlCommandlineLocation)) {
				$mysqlCommandlineLocation = "";
			}
		}
	}

	if(!length($mysqlCommandlineLocation)) {
		$mysqlCommandlineLocation = "/usr/bin/mysql";
	}

	print "Path to mysql (default: $mysqlCommandlineLocation):\n";
	$userResponse = <STDIN>;
	$userResponse =~ s/\n//g;
	if(length($userResponse)) {
		$mysqlCommandlineLocation = $userResponse;
	}

	if(!(-e $mysqlCommandlineLocation)) {
		die "mysql could not be located in $mysqlCommandlineLocation - please install it, for example using the following command line\n# yum install mysql\n\n";
	}
}

sub verifyMysqlServerInstalled {
	my @envPathList, $userResponse, $rpmPath, $cmdResponse;

	$rpmPath = "";
	@envPathList = split(/:/, $ENV{PATH});
	foreach (@envPathList) {
		if(!length($rpmPath)) {
			$rpmPath = $_."/rpm";
			if(!(-e $rpmPath)) {
				$rpmPath = "";
			}
		}
	}

	if(!length($rpmPath)) {
		print "The rpm command could not be located, please specify the path: ";
		$userResponse = <STDIN>;
		$userResponse =~ s/\n//g;
		if(!(-e $userResponse)) {
			die "The rpm command could not be located\n\n";
		}
	}

	if ($operatingSystem eq "suse") {
		$cmdResponse = `$rpmPath -q mysql`;
		if($cmdResponse =~ /not installed/i) {
			die "The mysql package is not installed - please install it using yast.  Example:\n" .
		      "yast2 -i mysql mysql-client mysql-shared perl-DBD-mysql perl-DBI perl-Data-ShowTable mysql-devel\n\n";
    }
	} else {
		$cmdResponse = `$rpmPath -q mysql-server`;
		if($cmdResponse =~ /not installed/i) {
			die "The mysql-server package is not installed - please install it using 'yum install mysql-server'.\n\n";
		}
	}
  
	$cmdResponse =~ s/\n//g;
	print "Found package $cmdResponse\n";
}

sub verifyDatabase {
  my $mysqlConnResponse;

  ## Verify mysql connectivity
  print "Verifying database connection...\n";

  #$mysqlConnResponse = `$mysqlCommandlineLocation --user=$mysqlUser --password=$mysqlPwd1 $mysqlDatabase --execute="SHOW TABLES" 2>&1`;
  $mysqlConnResponse = `$mysqlCommandlineLocation --user=$mysqlUser --password=$mysqlPwd1 --execute="SHOW DATABASES" 2>&1`;

  if($mysqlConnResponse =~ /ERROR/i) {
    die $mysqlConnResponse."\n\n";
  }

  print "Connected successfully!\n";
  
  ## Force MySQL service to be restarted automatically after a reboot
  `/sbin/chkconfig mysqld on`;    

}

sub createDatabase {
  my $mysqlConnResponse;

  $databaseName = $_[0];

  print "Creating database: ".$databaseName." ...\n";
  if(length($mysqlPwd1)) {
    $mysqlConnResponse = `$mysqlCommandlineLocation --user=$mysqlUser --password=$mysqlPwd1 --execute="CREATE DATABASE IF NOT EXISTS $databaseName" 2>&1`;
  } else {
    $mysqlConnResponse = `$mysqlCommandlineLocation --user=$mysqlUser --execute="CREATE DATABASE IF NOT EXISTS $databaseName" 2>&1`;
  }

  if($mysqlConnResponse =~ /ERROR/i) {
    die $mysqlConnResponse."\n\n";
  }
}

sub getHostName {

  print "MySQL hostname (default: localhost):\n";
  $mysqlHost = <STDIN>;
  chop $mysqlHost;

  if ($mysqlHost eq ""){
    $mysqlHost = "localhost";
  }
}

sub getDatabase {

  print "MySQL database (default: oreka):\n";
  $mysqlDatabase = <STDIN>;
  chop $mysqlDatabase;
  
  if ($mysqlDatabase eq ""){
    $mysqlDatabase = "oreka";
  }
}

sub getUser {

  print "MySQL user (default: root):\n";
  $mysqlUser = <STDIN>;
  chop $mysqlUser;

  if ($mysqlUser eq ""){
    $mysqlUser = "root";
  }
}

sub getPasswords {

  print "MySQL password:\n";
  $mysqlPwd1 = <STDIN>;
  chop $mysqlPwd1;

  print "MySQL password confirm:\n";
  $mysqlPwd2 = <STDIN>;
  chop $mysqlPwd2;

  while ($mysqlPwd1 ne $mysqlPwd2){
    print "Passwords do not match!\n";
  
    print "MySQL password:\n";
    $mysqlPwd1 = <STDIN>;
    chop $mysqlPwd1;
  
    print "MySQL password confirm:\n";
    $mysqlPwd2 = <STDIN>;
    chop $mysqlPwd2;
  }
}

## If the installation is silent, Java is installed to the default path, otherwise
## user is prompted for installation location
sub installJava {

  if ($installSilent == 0) {
      $JREPrompt = "\nDo you want install Java? (y/n)\n";  
      print $JREPrompt;
    
      $installJRE = <STDIN>;
      chop $installJRE;
    
      while ($installJRE ne 'y' && $installJRE ne 'n'){          
        print $JREPrompt;
        $installJRE = <STDIN>;
        chop $installJRE;
      }
    
      if ($installJRE eq 'y'){
        &installJRE();
      } else {
        &verifyJavaExistence();
      }   
   } 
   
   ## In silent mode, install Java to default path
   else {
      print "\nInstalling Java - JRE 1.7\n";
      &installJRE();
   }  		
   $javaVerified = 1;
}

## Check for Java, need >= JRE 1.6
## If this is a silent installation, the defaults will be assumed 
sub verifyJavaExistence {

  $oldDefaultJavaHome = "/opt/java/jre1.5.0";
  $jrePathPrompt = "\nEnter the path to your current Java installation, (default:$defaultJavaHome)\nThe right directory should have at least a jre and bin subdirectories\n";
  print $jrePathPrompt;
  $javaHome = $defaultJavaHome;
 
  if ($installSilent == 0) {  
     $javaHome = <STDIN>;
     chop $javaHome;

     if($javaHome eq "") 
     {
       $javaHome = $defaultJavaHome;
     }
     #while ($javaHome eq ""){
     #  print $jrePathPrompt;
     #  $javaHome = <STDIN>;
     #  chop $javaHome;
     #}
 
     ## Test for path's existence
     while (!-d $javaHome) {
       print "Directory ".$javaHome." does not exist, please enter the right path...\n";
       $javaHome = <STDIN>;
       chop $javaHome;
     }
  } else {   
  
     ## Check if java path exists
     if (!-d $javaHome) {
        $javaHome = $oldDefaultJavaHome;
        if (!-d $javaHome) {
           print "WARNING: *** Directory ".$javaHome." does not exist.  Tomcat will not run correctly!!!\n";
        }
     }
  }
  
  ## Make sure the Java executable is there too
  
  ## Need to make sure that the JRE is >= 1.6 - can not rely on $JAVA_HOME for this
  $javaExePath = $javaHome."/bin/java";  
  
  if (!-e $javaExePath){
    die "The Java executable does not seem to be at: ".$javaExePath."\nPlease verify your installation!\n";
  } else {
    print "Found the Java executable at: ".$javaExePath."\n";
  }
}

## Extract JRE from installer and install it
sub installJRE {

  ## For 32bit OS, the JRE is installed in jre1.7.0_02 sub-directory under the current 
  ## directory (where the installer is) 
  ## e.g. the JRE is installed in the /usr/java/jre1.7.0_02 directory. 
  ## Verify that the jre1.7.0_02 sub-directory is listed under the current directory. 

  ## 32-bit Java
  if ($typeOS==32) {
    $JRESubDir = "jre1.7.0_02";
    $JRESubDirPath = "./jre1.7.0_02";
    $JREgz = "jre-7u2-linux-i586.tar.gz";
  ## 64-bit Java
  } else {
    $JRESubDir = "jre1.7.0_04";
    $JRESubDirPath = "./jre1.7.0_04";
    $JREgz = "jre-7u4-linux-x64.tar.gz";  
  }  
 
   if ($installSilent == 0) {
      $jrePathPrompt = "Enter desired path to install Java - the JRE will be installed in a subdirectory named ".$JRESubDir."\n(default: /opt/java):\n";
      print $jrePathPrompt;
      $javaPath = <STDIN>;
      chop $javaPath;
   } else {
      $javaPath = "/opt/java"; 
      $jrePathPrompt = "\Java JRE will be installed in ".$javaPath."/".$JRESubDir."\n";
      print $jrePathPrompt;
   }   
  
   if ($javaPath eq "") {
     $javaPath = "/opt/java";
   }
  
  ## Test for path's existence
  if (!-d $javaPath) {
    print "\nDirectory ".$javaPath." does not exist, will create it...\n";    
    $pid = `mkdir $javaPath`;
  }
  
  ## Gunzip JRE then untar the tar file installer.  This will extract the files to 
  ## the $JRESubDirPath. 
  print "\nInstalling Java ".$JREgz."...\n";
  `$tar -xzf $JREgz`;

  ## Move it to installation path
  `mv $JRESubDirPath $javaPath`;

  ## Delete source file
  `rm -f $JREgz`;

  ## Set variable that will become JAVA_HOME
  $javaHome = $javaPath."/".$JRESubDir;
  
  print "\nJRE has been successfully installed in: ".$javaHome."\n";
}

## Ask if Tomcat should be installed.  If --silent is used, install it anyway.
sub verifyTomcat {

  if ($installSilent == 0) {
     $installTomcatPrompt = "\nDo you want to install Tomcat 7 (V.4 OR HIGHER IS REQUIRED)? (y/n)\n";
     print $installTomcatPrompt;

     $installTomcat = <STDIN>;
     chop $installTomcat;

     while ($installTomcat ne 'y' && $installTomcat ne 'n'){          
       print $installTomcatPrompt;
       $installTomcat = <STDIN>;
       chop $installTomcat;
     }
   }

   if ($installSilent == 1 || $installTomcat eq 'y'){
       &installTomcat();
     } else {
       &verifyTomcatExistence();
     }	
  
  $tomcatVerified = 1;

  &addTomcatService();
}

sub installTomcat { 

  ## The JRE is installed in jre1.7.0_02 sub-directory under the current directory (where the installer is).
  ## e.g. the JRE is installed in the /opt/java/1.7.0_02 directory.
  ## Verify that the jre1.7.0_02 sub-directory is listed under the current directory.

  print "\nInstalling Tomcat 7\n";
  $TomcatSubDir = "apache-tomcat-7.0.23";
  $TomcatSubDirPath = "./apache-tomcat-7.0.23";
  $TomcatTGZ = "apache-tomcat-7.0.23.tar.gz";
  $TomcatDir = "tomcat7";
 
  if ($installSilent == 0) { 
     $tomcatPathPrompt = "Enter the path for Tomcat installation (default: /opt).\nA subdirectory called tomcat7 will be created under the directory you enter (e.g.: /opt/tomcat7): \n";
     print $tomcatPathPrompt;
     $tomcatPath = <STDIN>;
     chop $tomcatPath;
  
     if ($tomcatPath eq ""){
       $tomcatPath = "/opt";
     }
  } else {
    $tomcatPath = "/opt";
  }   
  
  ## Test for path's existence
  if (!-d $tomcatPath) {
    print "Directory ".$tomcatPath." does not exist, will create it...\n";
    $pid = `mkdir $tomcatPath`;
  }
  
  ## Gunzip Tomcat then run the binary installer.  This will extract the files to 
  ## the $TomcatSubDirPath.   
  `$tar -xzf $TomcatTGZ`;              ## Extract
  `mv $TomcatSubDirPath $TomcatDir`;   ## Rename first
  `mv ./$TomcatDir $tomcatPath`;       ## Move
  `rm -f ./$TomcatTGZ`;                ## Delete source file

  ## Set variable that will become CATALINA_HOME
  $catalinaHome = $tomcatPath."/".$TomcatDir;

  ## Set JAVA_HOME and CATALINA_HOME and update CATALINA_OPTS in the tomcat startup script
  ## Also configure start and stop commands to run as tomcat user, by default
  &configureTomcatInitScript(1,0);
  ## Configure tomcat to use secure connection and shared lib
  &configureTomcatConfig($catalinaHome);
  
  print "\nTomcat has been successfully installed in: ".$catalinaHome."\n";
}

## Configure tomcat group/user as tomcat/tomcat by default
sub configureTomcatRunMode {

  ## Ask if Tomcat should be configured to run as default tomcat user, tomcat group.  
  ## This is the default behavior.  Otherwise, keep as root.
  if ($installSilent == 0) {
     $configureTomcatPrompt = "\nBy default, tomcat will be configured to run as user tomcat (group tomcat). Select 'y' to accept, 'n' to run tomcat as root (y/n)\n";
     print $configureTomcatPrompt;

     $configureTomcat = <STDIN>;
     chop $configureTomcat;

     while ($configureTomcat ne 'y' && $configureTomcat ne 'n'){          
       print $configureTomcatPrompt;
       $configureTomcat = <STDIN>;
       chop $configureTomcat;
     }

     if ($configureTomcat eq 'y'){
        $tomcatInstalledAsRoot = 0;
     } else {
        $tomcatInstalledAsRoot = 1;
     }     
  }

  if ($tomcatInstalledAsRoot==0) {
    
    print "Configuring Tomcat 7 to run as tomcat.tomcat...\n";
    
    ## Create tomcat group and user
    `$groupadd $tomcatGroup`;
    `$useradd -g $tomcatGroup $tomcatUser`; 
    
    ## Update user's environment with JAVA_HOME and CATALINA_HOME path
    if (!-e $tomcatUserHome) {
      `mkdir -p .$tomcatUserHome`;                  
    }
    
    ## Make tomcat directory accessible to tomcat user
    `$chown -Rf $tomcatGroup.$tomcatUser $catalinaHome`;
    ## Make logging directory accessible to tomcat user
    `$chown -Rf $tomcatGroup.$tomcatUser $loggingDir`;
    ## Make configuration directory accessible to tomcat user
    `$chown -Rf $tomcatGroup.$tomcatUser $orkwebConfigDir`;
    
  } else {
    ## Make tomcat script invoke Tomcat software as group/user root/root 
    &configureTomcatInitScript(0,$tomcatInstalledAsRoot);
  }             
          
}

sub verifyTomcatExistence {

  $tomcatPathPrompt = "\nEnter the path to your current Tomcat installation (default:$defaultCatalinaHome)\nThe right directory should have at least a bin subdirectory\n";

  if ($installSilent == 0) { 
     print $tomcatPathPrompt;
     $catalinaHome = <STDIN>;
     chop $catalinaHome; 
     if($catalinaHome eq "") 
     {
       $catalinaHome = $defaultCatalinaHome;
     }
     #while ($catalinaHome eq ""){
     #  print $tomcatPathPrompt;
     #  $catalinaHome = <STDIN>;
     #  chop $catalinaHome;
     #}
     
     ## Test for path's existence
     while (!-d $catalinaHome) {
       print "Directory ".$catalinaHome." does not exist, please enter the right path...\n";
       $catalinaHome = <STDIN>;
       chop $catalinaHome;
     }
     
  }  else {
     $catalinaHome = $defaultCatalinaHome;
  } 
  
  
  ## Make sure the Tomcat executable is there too
  $tomcatExePath = $catalinaHome."/bin/startup.sh";  
  
  if (!-e $tomcatExePath){
    die "The Tomcat startup.sh executable does not seem to be at: ".$tomcatExePath."\nPlease verify your installation!\n";
  } else {
    print "Found the Tomcat executable at: ".$tomcatExePath."\n";
  }

  ## Look for the tomcat service startup script
  $initd_tomcat_startup = "/etc/init.d/tomcat";

  if (!-e $initd_tomcat_startup)
  {
     &configureTomcatInitScript(1,0);
  } 
  else 
  {
    `rm $initd_tomcat_startup`;  # for now, force deletion and reinstall
    &configureTomcatInitScript(1,0);
  }
  
  print "\nNOTE: if you need to configure Tomcat to use secure mode (https), contact support\@orecx.com\n";
  if ($installSilent == 0) {  
     print "Press any key to continue.\n";
     $keyPress = <STDIN>;
     chop $keyPress;
}
}


## Create /etc/init.d/tomcat if not there and modify it depending on user input
sub configureTomcatInitScript {

  $createScript = $_[0];
  $configureRunMode = $_[1];     # For configuring how to run tomcat 

  $initd_dir = "/etc/init.d/";

  if (!-d $initd_dir) {
    print "Creating directory: ".$initd_dir."\n";
    mkdir($initd_dir) || die "Cannot mkdir newdir: $!"." ".$initd_dir;
  }

  if ($createScript == 1) {
    print "Copying tomcat init script to: ".$initd_dir."\n";
    copy("./tomcat",$initd_dir) or die("**** Operation failed\n");
  }

  $tomcat_script = $initd_dir."tomcat";

  open (IN, "$tomcat_script") or die "Couldn't open $tomcat_script: $!";
  open (OUT, "> $tomcat_script.bak") or die "Couldn't open $tomcat_script: $!";

  if ($configureRunMode == 0) {

    if ($createScript == 0) {
      print "Updating JAVA_HOME, CATALINA_HOME and CATALINA_OPTS in existing /etc/init.d/tomcat script\n";
    }

    print "Configuring $initd_tomcat_startup init script\n";

  ## Configure tomcat memory usage based on total system memory
  $totalMemory = `cat /proc/meminfo | grep MemTotal`;
  $totalMemory =~ s/[a-z]//g;
  $totalMemory =~ s/[A-Z]//g;
  $totalMemory =~ s/://g;
  $totalMemory =~ s/ //g;
  $totalMemory =~ s/\n//g;

  $tomcatMemory = "256m";    
  if ($totalMemory > 700000) {
    $tomcatMemory = "512m";
  } elsif ($totalMemory < 500000) { 
    print "\n**** WARNING: total system memory is too low ($totalMemory kB). Tomcat will be set to use 256MB RAM. *****\n\n";
  }

    ## Update following paths in tomcat startup script (JAVA_HOME and CATALINA_HOME)
    ## export JAVA_HOME=/opt/java/jre1.7.0_02
    ## export CATALINA_HOME=/opt/tomcat7
    ## Update CATALINA_OPTS to ensure that 512MB of Java memory is reserved for tomcat
  while(<IN>){
    s/JAVA_HOME=.*/JAVA_HOME=$javaHome/;
    s/CATALINA_HOME=.*/CATALINA_HOME=$catalinaHome/;
    s/CATALINA_OPTS="-Dbuild.compiler.emacs=true"*/CATALINA_OPTS="-Xms$tomcatMemory -Xmx$tomcatMemory -Dbuild.compiler.emacs=true"/;

    ## If operating system is Linux SuSE, perform some changes to tomcat file
    if ($operatingSystem eq "suse") {
      s/\. \/etc\/rc.d\/init.d\/functions/# \. \/etc\/rc.d\/init.d\/functions/;
      s/\. \/etc\/sysconfig\/network/# \. \/etc\/sysconfig\/network/;
      s/\[ \$\{NETWORKING\} = \"no\" \] \&\& exit 0/# \[ \$\{NETWORKING\} = \"no\" \] \&\& exit 0/;
    }
    print OUT;
  }
  }  
  elsif ($tomcatInstalledAsRoot == 1) {
      print "Configuring $initd_tomcat_startup init script to run Tomcat as root\n";
  
      ## Modify how script is run, as tomcat or root user
      while(<IN>){
        s/\/bin\/su - tomcat //;                             # Remove part that calls scripts as tomcat user
        print OUT;
      }
  }

  close(IN);
  close(OUT);

  ## copy the modified .bak file contents to the original file,
  ## thereby overwriting the original
  rename("$tomcat_script.bak","$tomcat_script") || die $!;
  
  ## make sure it is executable
  `chmod +x $tomcat_script`;
  
  ## Add JAVA_HOME, CATALINA_HOME and CATALINA_OPTS to CATALINA_HOME/bin/catalina.sh
  &updateCatalinaFile($tomcatMemory);

}

## Configure Tomcat configuration: 
##  - Update server.xml file to add support for secure SSL through https on port 
##    8443 and keystore file, as well as maxPostSize setting 
##  - Update catalina.properties file to add access to shared/lib folder
sub configureTomcatConfig {

  $tomcatPath = $_[0];
  $tomcatConfigPath = "$tomcatPath/conf";
  $orecxPath = "$tomcatPath/OrecX";  

  #print "Configuring https (port 8443) and keystore files for OrkWeb secure mode...\n";
  #print "Tomcat path: $tomcatConfigPath\n";
  #print "OrecX path: $orecXPath\n";

  if (!-d $tomcatConfigPath) {
     print("Could not find Tomcat directory.  Will not be able to configure server.xml and keystore.\n");
     return;
  }

  ## Copy server.xml to $tomcat/conf folder  
  #print "Configuring server.xml file...\n";
  copy("$tomcatConfigPath/server.xml","$tomcatConfigPath/server.xml.ori") or print("Warning: did not find $tomcatConfigPath/server.xml file!\n"); 
  copy("./server.xml",$tomcatConfigPath) or print("Warning: could not create new server.xml due to error: $! \n Installation may have problems.\n"); 
  
  ## Copy catalina.properties to $tomcat/conf folder  
  #print "Configuring catalina.properties file...\n";
  copy("$tomcatConfigPath/catalina.properties","$tomcatConfigPath/catalina.properties.ori") or print("Warning: did not find $tomcatConfigPath/catalina.properties file!\n"); 
  copy("./catalina.properties",$tomcatConfigPath) or print("Warning: could not create new catalina.properties due to error: $! \n Installation may have problems.\n"); 

  ## Install .keystore under $Tomcat/OrecX folder  
  #print "Configuring OrecX/.keystore file...\n";
  if (!-d $orecxPath) {
     $cmd = "mkdir $orecxPath";
     `$cmd`;
     if (!-d $orecxPath) {
        print("Warning: could not create OrecX folder.  OrkWeb will not work in secure mode.\n");
        return;      
     }
  }

  copy("./.keystore",$orecxPath) or print("Warning: could not create keystore file: $! \n OrkWeb will not work in secure mode.\n");

}

## Add Tomcat as service
sub addTomcatService {
  
  if(!-e '/sbin/chkconfig')
  {
	# this is probably not a redhat derivative, for now do not install as a service
	return;
  }
  
  $tomcatService = '';
  
  if ($installSilent == 0) {
     $tomcatServicePrompt = "\nDo you want to install Tomcat as a service? (y/n)\n";
     print $tomcatServicePrompt;

     $tomcatService = <STDIN>;
     chop $tomcatService;

     while ($tomcatService ne 'y' && $tomcatService ne 'n'){          
       print $tomcatServicePrompt;
       $tomcatService = <STDIN>;
       chop $tomcatService;
     }
  } else {
     $tomcatServicePrompt = "\nInstalling Tomcat as a service...\n";
     print $tomcatServicePrompt;
  }
  
  if ($tomcatService eq 'y' || $installSilent == 1){

    $tomcatInstalledAsService = 1;
    $ChkconfigAddTomcatService = "chkconfig --add tomcat";
    print "Adding Tomcat Service: $ChkconfigAddTomcatService\n";
    `$ChkconfigAddTomcatService`;
    $switchOnTomcatService = "chkconfig tomcat on";
    print "Making Tomcat service start at bootup: $switchOnTomcatService\n";
    `$switchOnTomcatService`;
  }
}

## Create the config files in /etc/orkweb
sub updateOrkwebConfig {

  if (!-d $orkwebConfigDir) {
    print "Creating orkweb configuration directory: ".$orkwebConfigDir."\n";
    mkdir($orkwebConfigDir) || die "Cannot mkdir newdir: $!"." ".$orkwebConfigDir;
  }
  
  print "Copying database.hbm.xml to: ".$orkwebConfigDir."\n";
  print "Copying logging.properties to: ".$orkwebConfigDir."\n";
 
  copy("./database.hbm.xml", $orkwebConfigDir) or die ("Could not copy database.hbm.xml to $orkwebConfigDir");
  copy("./logging.properties", $orkwebConfigDir) or die ("Could not copy logging.properties to $orkwebConfigDir");

  $database = $orkwebConfigDir."database.hbm.xml";
  $logging = $orkwebConfigDir."logging.properties";
  
  &updateLoggingConfig();
}


## Modify database.hbm.xml
sub updateHibernateConfig {

    open (IN, "$database") or die "Couldn't open $database: $!";
    open (OUT, "> $database.bak") or die "Couldn't open $database: $!";

    while(<IN>){
      s/jdbc:mysql:\/\/localhost\/test/jdbc:mysql:\/\/$mysqlHost\/$mysqlDatabase/;
      s/password<\/property>/$mysqlPwd1<\/property>/;
      s/username\">root/username\">$mysqlUser/;

      print OUT;
    }

    close(IN);
    close(OUT);

    ## copy the modified .bak file contents to the original file,
    ## thereby overwriting the original
    rename("$database.bak","$database") || die $!;
  }


## Modify logging.properties
sub updateLoggingConfig {

  if (!-d $loggingDir) {
      print "Creating orkweb logging directory in: ".$loggingDir."\n";
      mkdir($loggingDir) || die "Cannot mkdir newdir: $!"." ".$loggingDir;
  }
  
  ## Adjust privileges
  $chmdCmd = "chmod go-rx ".$loggingDir;
  `$chmdCmd`;

  open (IN, "$logging") or die "Couldn't open $logging: $!";
  open (OUT, "> $logging.bak") or die "Couldn't open $logging: $!";

  while(<IN>){
    s/c:\/orkweb.log/$loggingDir\/orkweb.log/;
    s/c:\/orklicense.log/$loggingDir\/orklicense.log/;

    print OUT;
  }

  close(IN);
  close(OUT);

  ## copy the modified .bak file contents to the original file,
  ## thereby overwriting the original
  rename("$logging.bak","$logging") || die $!;
}

sub deployWebAppsToTomcat {

	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
	$year = $year + 1900;
	$mon = $mon + 1;
	$timestamp = "$year-$mon-$mday\_$hour$min$sec";
	$webAppsPath = $catalinaHome."/webapps/";
	$orktrackPath = $webAppsPath."orktrack";
        $orkwebPath = $webAppsPath."orkweb";
	$tomcatSharedPath = $catalinaHome."/shared/";
	$sharedLibPath = $tomcatSharedPath."lib";

	$shouldBackupSharedLib = 0;

	if(-e $orktrackPath)
	{
		$orktrackBackupPath = "/tmp/orktrack.$timestamp";
		print "Taking a backup of orktrack webapp to $orktrackBackupPath\n";
		`mv $orktrackPath $orktrackBackupPath`;	
		$shouldBackupSharedLib = 1;
	}
	if(-e $orkwebPath)
	{
		$orkwebBackupPath = "/tmp/orkweb.$timestamp";
		print "Taking a backup of orkweb webapp to $orkwebBackupPath\n";
		`mv $orkwebPath $orkwebBackupPath`;	
                $shouldBackupSharedLib = 1;
	}
	if($shouldBackupSharedLib == 1)
	{
		$sharedLibsBackupPath = "/tmp/oreka-shared-libs.$timestamp";
                print "Taking a backup of Java shared libs to $sharedLibsBackupPath\n";
		`mv $sharedLibPath $sharedLibsBackupPath`;
	}

	print "Deploying orktrack and orkweb applications to tomcat webapps directory\n";
	mkdir $orktrackPath or die ("Could not create $orktrackPath directory");
	mkdir $orkwebPath or die ("Could not create $orkwebPath directory");
	mkdir $sharedLibPath;
	`$unzip orkweb.war -d $orkwebPath`;
	`$unzip orktrack.war -d $orktrackPath`;
    `$unzip lib.zip -d $tomcatSharedPath`;
}


## Modify orktrack and orkweb - web.xml files
sub updateAppWebXML {

  $orktrackWebXml = $catalinaHome."/webapps/orktrack/WEB-INF/web.xml";
  $orkwebWebXml = $catalinaHome."/webapps/orkweb/WEB-INF/web.xml";

  ## Open look for c:/oreka/ and replace by /etc/orkweb/
  $oldPath = 'c:/oreka/';

  if (-e $orktrackWebXml){
    open(IN, "$orktrackWebXml") or die("Unable to open file ".$orktrackWebXml);
    open(OUT, "> $orktrackWebXml.bak") or die("Unable to open file ".$orktrackWebXml."bak");

    while(<IN>){
      s/$oldPath/$orkwebConfigDir/;
      s/C:\/Program\ Files\/Apache\ Software\ Foundation\/Tomcat\ 7.0/$catalinaHome/;
      print OUT;
    }
    
    close(IN);
    close(OUT);

    ## copy the modified .bak file contents to the original file,
    ## thereby overwriting the original
    rename("$orktrackWebXml.bak", "$orktrackWebXml") || die $!;
  }
  else
  {
	print("orktrack web.xml file could not be found, please contact support\@orecx.com\n");
	exit();
  }

  if (-e $orkwebWebXml){
    open(IN, "$orkwebWebXml") or die("Unable to open file ".$orkwebWebXml);
    open(OUT, "> $orkwebWebXml.bak") or die("Unable to open file ".$orkwebWebXml."bak");

    while(<IN>){
      s/$oldPath/$orkwebConfigDir/;
      s/C:\/Program\ Files\/Apache\ Software\ Foundation\/Tomcat\ 7.0/$catalinaHome/;
      print OUT;
    }
    
    close(IN);
    close(OUT);

    ## copy the modified .bak file contents to the original file,
    ## thereby overwriting the original
    rename("$orkwebWebXml.bak", "$orkwebWebXml") || die $!;
  }
  else
  {
        print("orkweb could not be found in the Tomcat webapps directory, please contact support\@orecx.com\n");
        exit();
  }

}

## Update JAVA_HOME, CATALINA_HOME, CATALINA_OPTS in catalina.sh file.  Add them
## if they do not exist.  These would be used regardless of what user starts Tomcat.
## Expects Tomcat Memory requirements as parameter (e.g. "512m") 
## Example:
##    export JAVA_HOME=/opt/java/jre1.7.0_02
##    export CATALINA_HOME=/opt/tomcat7
##    export CATALINA_OPTS="-Xms512m -Xmx512m -Dbuild.compiler.emacs=true -Dfile.encoding=UTF-8"
sub updateCatalinaFile() {

  my $tomcatMemory = shift;

  $javaHomeLine     = 'export JAVA_HOME=';
  $catalinaHomeLine = 'export CATALINA_HOME=';
  $catalinaOptsLine = 'export CATALINA_OPTS="-Dbuild.compiler.emacs=true -Dfile.encoding=UTF-8"';

  $matchedJava = $matchedCatalina = $matchedOpts = "";
  $catalinaFile = $catalinaHome."/bin/".$catalinaFile;

  ## Back up catalina.sh file to catalina.sh.datetime
  my $dt=strftime('%Y%m%d_%H%M%S', localtime);
  copy("$catalinaFile","$catalinaFile.$dt") || die $!;

  open (my $inputFH, "$catalinaFile") or die "Couldn't open $catalinaFile: $!";

  print "Updating JAVA_HOME, CATALINA_HOME and CATALINA_OPTS in existing $catalinaFile file... \n";

  while(<$inputFH>) {

    my $updateLineNumber = 0;
    $found = s/export JAVA_HOME=.*/export JAVA_HOME=$javaHome/ if !/^\s*#/;
    if ($found ne '') {
       $matchedJava = $found;
       $updateLineNumber = 1;
    }
    $found = s/export CATALINA_HOME=.*/export CATALINA_HOME=$catalinaHome/ if !/^\s*#/;
    if ($found ne '') {
       $matchedCatalina = $found;
       $updateLineNumber = 1;
    }
    $found = s/export CATALINA_OPTS="-Dbuild.compiler.emacs=true -Dfile.encoding=UTF-8"*/CATALINA_OPTS="-Dbuild.compiler.emacs=true -Dfile.encoding=UTF-8 -Xms$tomcatMemory -Xmx$tomcatMemory"/ if !/^\s*#/;
    if ($found ne '') {
       $matchedOpts = $found;
       $updateLineNumber = 1;
    }
    
    ## Update line number if entry found
    if ($updateLineNumber eq 1) {
       my $lineNumber = $inputFH->input_line_number();
       if ($lineNumber > $lastFoundEntryLineNumber) {
         $lastFoundEntryLineNumber = $lineNumber;
       }
    }
  }

  close($inputFH);

  ## If at least one of the variables was not updated because it did not exist,
  ## add it and any other the missing one.
  if (($matchedJava eq '') || ($matchedCatalina eq '') || ($matchedOpts eq '')) {

     ## Determine line where entry(ies) should be added
     if ($lastFoundEntryLineNumber > 0) {
        $lineNumber = $lastFoundEntryLineNumber;
     } else {
        $lineNumber = &getInsertLineNumber($catalinaFile);
     }
     
     # Open file and update contents
     open (my $inputFH, "$catalinaFile") or die "Couldn't open $catalinaFile: $!";
     open (OUT, "> $catalinaFile.bak") or die "Couldn't open $catalinaFile: $!";

     # Print lines before the line to insert...
     while(<$inputFH>) {
       print OUT $_; 
       last if $. == $lineNumber;
     }

     # Insert new lines...
     if ($matchedJava eq '') {
        print OUT $javaHomeLine.$javaHome."\n"; 
     }
     if ($matchedCatalina eq '') {
        print OUT $catalinaHomeLine.$catalinaHome."\n"; 
     }
     if ($matchedOpts eq '') {
        $catalinaOptsLine =~ s/"-Dbuild.compiler.emacs=true -Dfile.encoding=UTF-8"/"-Dbuild.compiler.emacs=true -Dfile.encoding=UTF-8 -Xms$tomcatMemory -Xmx$tomcatMemory"/; 
        print OUT $catalinaOptsLine."\n";
     }
     print OUT "\n";

     # Print lines after the inserted lines...
     while(<$inputFH>) {
       print OUT $_;
     }

     close(OUT);
     close($inputFH);

     ## Copy the modified .bak file contents to the original file overwriting it
     rename("$catalinaFile.bak","$catalinaFile") || die $!;
  
     ## make sure it is executable
     `chmod +x $catalinaFile`;

  }

}

## Get line number in file where to insert environment variables.
## This should be just before the first non-comment/non-blank line. 
sub getInsertLineNumber {

   my $inputFile = shift;

   open (my $file, "$inputFile") or die "Couldn't open $file: $!";

   while (my $line = <$file>) {

      if ($line =~ /^\s*$/) {
         $blankLineNumber = $file->input_line_number();   ## blank line number
      }
      elsif ($line =~ /^\s*#/) {
         $commentLineNumber = $file->input_line_number(); ## comment line number
      } else {
         $dataLineNumber = $file->input_line_number();    ## first non-blank/comment line
         last;
      }
      next;
   }

   close($file);

   ## Determine insertion line
   if ($blankLineNumber == 0) {
      $insertLineNumber = $dataLineNumber;
   } else {
      $insertLineNumber = $blankLineNumber;
   }

   return $insertLineNumber;
}
