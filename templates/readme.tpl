QDGC level GIVE_LEVEL - GIVE_NAME (GIVE_CODE)
- - - - - - - - - - - - - - - - - - - - - - - - - - - -
                                      
QDGC represents a way of making (almost) equal area squares covering a
specific area to represent specific qualities of the area covered. The 
squares themselves are based on the degree squares covering earth. Around
the equator we have 360 longitudinal lines , and from the north to the
south pole we have 180 latitudinal lines. Together this gives us 64800
segments or tiles covering earth.

The geopackage file(s) provided are named by country and zipped. Examples are:
-qdgc_zambia.zip
-qdgc_tanzania.zip
-qdgc_ghana.zip
-etc

Within each geopackage file you will find a number of tables with these names:

-tbl_qdgc_01
-tbl_qdgc_02
-tbl_qdgc_03
-tbl_qdgc_04
-tbl_qdgc_05
-
etc

Metadata
--------
Geodata	GCS_WGS_1984
		Datum: D_WGS_1984
		Prime Meridian: 0

ARAEA	Calculated with PostgIS fungtion st_area:

	(st_area(st_transform(geom, 102008))/1000000)
		FME is using the AZMEA (ALambert Azimuthal Equal
    Area Projection) for area calculations. You are 
    adviced to recalculate the areas using a more local
		projection if the area calculation is important
		for your work.


Copyright
---------
GNU GPL License is the closest one. Free of charge, free to use, free to
change and free to distribute.


Conditions
----------
Delivered to the user as-is. No guarantees. If you find errors, please tell
and I will try to fix it.


Thankyou
--------
FME - Special thanks this time goes to FME which
      has provided the Tanzania Conservation Resource
      Centre with two licenses of FME under their Grant
      Program Application.
Tanzania Wildlife Research Institute 
Dept of Biology, NTNU, Norway
Norwegian Environment Agency
Eivin Røskaft
Steven Prager
Howard Frederick
Julian Blanc
Honori Maliti

                          
References
----------
* http://en.wikipedia.org/wiki/QDGC
* http://www.mindland.com/wp/projects/quarter-degree-grid-cells/about-qdgc/
* http://en.wikipedia.org/wiki/Lambert_azimuthal_equal-area_projection
* http://www.safe.com
* http://www.wingware.com/


Regards,

Ragnvald Larsen
Trondheim 5th of December, 2014

ragnvald@mindland.com
www.mindland.com
