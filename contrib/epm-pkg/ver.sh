# Input DEF file for: mkver.pl.  All variables must have "export "
# at the beginning.  No spaces around the "=".  And all values
# enclosed with double quotes.  Variables may include other variables
# in their values.

# Set this to latest version of mkver.pl (earlier DEF files should
# still work with newer versions of mkver.pl)
export MkVer="2.2"

export ProdName="rsnapshot"
# One word [-a-z0-9]
# Required
# %provides ProdName

export ProdAlias="rsnapshot"
# One word [-a-z0-9]

export ProdVer="1.5.1"
# [0-9]*.[0-9]*{.[0-9]*}
# Requires 2 numbers, 3'rd number is optional
# First, Major changes:
#        Older projects should work, but they may need to be upgraded.
#        Newer projects will not work with older versions of git-proj
# Second, Minor changes, fixes, additions. Things probably won't break
#        for projects with the same Major version number.
# Third, Internal refactoring changes, changes in test messages, doc changes
# %version ProdVer

export ProdRC=""
# Release Candidate ver. Can be one or two numbers.
# If set and RELEASE=1
  # %release rc.ProdRC

export ProdBuild="2"
# [0-9.]*
# Required
# If RELEASE=1, and ProdRC=""
  # %release test.ProdBuild

# Generated: ProdBuildTime=YYYY.MM.DD.hh.mm
  # If RELEASE=0, or empty, or unset, then use
  # current time (UTC): %Y.%m.%d.%H.%M
    # %release ProdBuildTime

export ProdSummary="rsnapshot is a filesystem snapshot utility based on rsync."
# All on one line (< 80 char)
# %product ProdSummary

export ProdDesc="rsnapshot makes it easy to make periodic snapshots of local machines, and remote machines over ssh. The code makes extensive use of hard links whenever possible, to greatly reduce the disk space required."
# All on one line
# %description ProdDesc

export ProdVendor="TurtleEngr"
# Required
# %vendor ProdVendor

export ProdPackager="$USER"
# Required
# %packager ProdPackager

export ProdSupport="turtle.engr\@gmail.com"
# Appended to %vendor

export ProdCopyright=""
# Current year if not defined
# %copyright ProdCopyright

export ProdDate=""
# 20[0-9][0-9]-[01][0-9]-[0123][0-9]
# Current date (UTC) if empty

export ProdLicense="dist/usr/local/share/doc/rsnapshot/LICENSE"
# Required
# %license ProdLicense

export ProdReadMe="dist/usr/local/share/doc/rsnapshot/README.md"
# Required
# %readme ProdReadMe

# Third Party (if any) If repackaging a product, define these:
export ProdTPVendor="rsnapshot"
# Appended to
export ProdTPVer="1.5.1"
# Appended to
export ProdTPCopyright="dist/usr/share/doc/rsnapshot/LICENSE"
# Appended to %copyright

export ProdRelServer="moria.whyayh.com"
export ProdRelRoot="/rel"
export ProdRelCategory="software/ThirdParty/$ProdName"
# Generated: ProdRelDir=$ProdRelRoot/released/$ProdRelCategory
# Generated: ProdDevDir=$ProdRelRoot/development/$ProdRelCategory

# Generated: ProdTag=tag-ProdVer-ProdBuild
# (All "." in ProdVer converted to "-")

# Generated: ProdOSDist=mx
# Generated: ProdOSVer=19
# Generated: ProdOS=mx19
# Generated: mx=1
# Generated: mx19=1
#       OSDist  OSVer
# linux
#       deb
#       ubuntu  16,18
#       mx      19,20
#       rhes
#       cent
#       fc
# cygwin
#       cygwin
# mswin32
#       win     xp
# solaris
#       sun
# darwin
#       mac

# Generated: ProdArch
# i386
# x86_64

# Output file control variables. (Unused types can be removed.)
# The *File vars can include dir. names
# The *Header and *Footer defaults are more complete than what is
# shown here.

export envFile="ver.env"
export envHeader=""
export envFooter="export CurLogName=$USER\n"

export epmFile="ver.epm"
export epmHeader="%include contrib/epm-pkg/$ProdOSDist.require"
export epmFooter="%include contrib/epm-pkg/epm.list"

export hFile="ver.h"
export hHeader=""
export hFooter=""

export javaPackage="DIR.DIR.DIR"
export javaInterface="ver"
export javaFile="ver.java"
export javaHeader=""
export javaFooter=""

export csNamespace="Supernode"
export csClass="ver"
export csFile="ver.cs"
export csHeader=""
export csFooter=""

export makFile="ver.mak"
export makHeader=""
export makFooter="CurLogName = $USER\n"

export plFile="ver.pl"
export plHeader=""
export plFooter=""

export xmlFile="ver.xml"
export xmlHeader=""
export xmlFooter=""
