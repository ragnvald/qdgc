#*******************************************************************
# Longitude/Latitude to Quarter Degree Grid Cell standard conversion 
# utility  
#
# The utility will accept the path of a .dbf-file as an argument. By
# setting the QDGC level the script will use the LON/LAT values to 
# produce a QDGC string value which is inserted into the QDGC column
# of the .dbf-file.
#
# Delivered as-is. If it works - fine for you. If it fails - too bad. 
# No are given guarantees whatsoever. If you use this program for 
# illegal purposes - don't blame me.
# 
# License type is Gnu GPL. Copy, distribute and change freely. Keep
# the author in mind for crediting. Come to think of it, use this 
# reference:
#
# R. Larsen, T. Holmern, S. D. Prager, H. Maliti and E. Roskaft 
#     (2009) Using the extended quarter degree grid cell system 
#     to unify mapping and sharing of biodiversity data, African
#     Journal of Ecology. Volume 47, Issue 3 , Pages 382 - 392
#
# Author Ragnvald Larsen, Dept of Biology, NTNU (www.bio.ntnu.no)
# ragnvald(at)mindland.com
#
# Version 0.6 (01.12.2009)



#*******************************************************************
# Import libraries 

# Standard libraries
import sys, os, math, datetime, time
from qdgc_lib import *

# Library dbfpy to read .dbf-files 
# This one needs to be downloaded and installed
# http://dbfpy.sourceforge.net/
from dbfpy import dbf

if len(sys.argv) <> 3:
    
    print """
NAME
    Countless Calculate DBF Conversion Utility
    Version 0.6 - 01.12.2009
    
CONTACT
    Ragnvald Larsen: ragnvald@mindland.com
    
FILE
    lonlat2qdgc.exe 
    
INSTALL
    This is a compiled Python 2.7 program. To run it you are 
    advised to place the file lonlat2qdgc.exe in a separate
    folder. C:\bin\lonlat2qdgc\ would be swell. Then open
    the command line tool in windows and run the file
    according to the SYNTAX below.
    
DESCRIPTION
    The program accepts a .dbf file as input and modifies the 
    contents of the file. LON and LAT column values are used
    to generate a QDGC string on a level determined by the
    users input.
    
    Read more here:
    http://www.qdgc.org
    
    No warranties. Use at own risk. Do not use on your original
    files without having a backup.
    
REFERENCE
    R. Larsen, T. Holmern, S. D. Prager, H. Maliti and E. 
    Roskaft (2009) Using the extended quarter degree grid 
    cell system to unify mapping and sharing of biodiversity 
    data, African Journal of Ecology. Volume 47, Issue 3 , 
    Pages 382 - 392
    
    Read more on QDGC levels at Wikipedia:
    http://en.wikipedia.org/wiki/QDGC
    
SYNTAX    
    lonlat2qdgc [drive:][path][filename] [QDGC level]
        
    [drive:][path][filename]     input .dbf-file to be calculated
    
    [QDGC level]                 Quarter Degree Grid Cell level 
                                 to be calculated. 
    
    The input .dbf-file should have the following columns:
    
    LON  - FLOAT
    LAT  - FLOAT
    QDGC - STRING
    
    Any values in the QDGC column will be overwritten with the
    new QDGC value.
    """

else:
    
    dbf_file   =   sys.argv[1]
    
    qdgc_level =   int(sys.argv[2])
    
    
    #*******************************************************************
    # Set input file and make the import class connect to the database. 
    # Get ready for magic.
    
    # Path to file. Must have columns LON, LAT and QDGC. LON/LAT types
    # should be set to N (numeric). ArcGis normaly sets it to F instead.
    # Can easily be changed in an editor with hex edit capabilities.
    db = dbf.Dbf(dbf_file)
    
    # QDGC level to be calculated (http://en.wikipedia.org/wiki/QDGC)
    qdgc_leveltocalculate = qdgc_level
    
    
    #--------------------------------------------------------------------------
    #MAIN
    
    #Read all records in the database and iterate through till the bitter end
    for rec in db:
        #Get values for longitude and latitude - given that their names are LON and LAT
        lon_to_calculate = rec["LON"]
        lat_to_calculate = rec["LAT"]
        
        #Set QDGC column (given that is the name) value with results of the functions above
        rec["QDGC"] = qdgc(lon_to_calculate,lat_to_calculate,qdgc_leveltocalculate)
    
        #Store the data
        rec.store()
        
        #Empty the record and prepare for another round
        del rec
    
    #Yeah... the DB should be closed. Polite thing to do.
    db.close()
    
    print "OK!"