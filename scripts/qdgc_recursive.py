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


#Math is used in this one
import math
import fmeobjects


#*******************************************************************
# Numerical representation of lat-lon
#
# Input: Longitude, Latitude
# 38.98754324/-9.87548764
#
# Output: Absolute referense to degree square
# E038S09?
#
def get_lonlat(lon_value,lat_value):

    #Put character in front of longitudal value
    if lon_value < 0:
        square = 'W'
    else:
        square = 'E'
            
    
    #Find absolute value for longitude
    lon_string=str(int(abs(lon_value)))


    #The longitudal value of the square is printed with three decimals
    square = square + (lon_string).zfill(3)

    

    #Put character in front of latitudal value
    if  lat_value < 0 :
        square = square + 'S'
    else:
        square = square + 'N'


    #find absolute value for latitude
    lat_string=str(int(abs(lat_value)))

    #find int lat. Remember that latitudes absolute values never excceed 90
    square = square + (lat_string).zfill(2)
    
    return square
        
        
#*******************************************************************
# RQDGC - recursive quarter degree grid cell
#
# Input: Latitude, Longitude, depth in powers of two, starting string
# -9.87548764, 38.98754324, 5, ""
#
# Output: DDDBB
#
# Obs!: This function places origo in the cell in the upper left
# in the southern hemisphere and in the lower left corner
# in the norther hemisphere. Is this ok?
def get_recursive_qdgc(lon_value,lat_value,depth,square):

    #remove all but the decimals (eg: 30.54 -> 0.54)
    #this also takes care of values below zero
    if  lon_value >1 :
        lon_value = lon_value - math.floor(lon_value)
    elif (lon_value<-1):
        lon_value = lon_value + abs(math.ceil(lon_value))

    #remove all but the decimals (eg: 30.54 -> 0.54)
    #this also takes care of values below zero
    if  (lat_value > 1):
        lat_value = lat_value - math.floor(lat_value)
    elif (lat_value<-1):
        lat_value = lat_value + abs(math.ceil(lat_value))


    #check which of the 4 squares the value fals within
    #Q1 - - - - - - - - - - - - - - - - - - - - - - - - - -
    if ((lon_value>=0) and (lat_value>=0)):
    
        #upper left - A
        if ((lon_value <0.5) and (lat_value>=0.5)):
            square =  square + 'A'
    
            lon_value=lon_value*2
            lat_value=(lat_value-0.5)*2
        
        
        #upper right - B
        elif ((lon_value>=0.5) and (lat_value>=0.5)):
            square = square + 'B'
    
            lon_value=(lon_value-0.5)*2
            lat_value=(lat_value-0.5)*2

            
        #lower left - C
        elif ((lon_value<0.5) and (lat_value<0.5)):
            square = square + 'C'
    
            #both values are doubled
            lat_value=lat_value*2
            lon_value=lon_value*2

            
        #lower right - D
        elif ((lon_value>=0.5) and (lat_value<0.5)):
            square =  square + 'D'
    
            lon_value=(lon_value-0.5)*2
            lat_value=lat_value*2

    
    # Q2 - - - - - - - - - - - - - - - - - - - - - - - - - -
    elif ((lon_value>=0) and (lat_value<=0)):
    
        # upper left - A
        if ((lon_value <0.5) and (lat_value>-0.5)):
            square = square + 'A'
    
            lon_value=lon_value*2
            lat_value=lat_value*2
            
        #upper right - B
        elif ((lon_value>=0.5) and (lat_value>-0.5)):
            square = square + 'B'
    
            lon_value=(lon_value-0.5)*2
            lat_value=lat_value*2

        #lower left - C
        elif ((lon_value<0.5) and (lat_value<=-0.5)):
            square = square + 'C'
    
            lon_value=lon_value*2
            lat_value=(lat_value+0.5)*2
            
        #lower right - D
        elif ((lon_value>=0.5) and (lat_value<=-0.5)):
            square = square + 'D'
    
            lon_value=(lon_value-0.5)*2
            lat_value=(lat_value+0.5)*2
            
    
    # Q3 - - - - - - - - - - - - - - - - - - - - - - - - - -
    elif ((lon_value<=0) and (lat_value<=0)):
    
        #upper left - A
        if ((lon_value<=-0.5) and (lat_value>-0.5)):
            square = square + 'A'
    
            lon_value=(lon_value+0.5)*2
            lat_value=lat_value*2
            
        #upper right - B
        elif ((lon_value>-0.5) and (lat_value>-0.5)):
            square = square + 'B'
    
            lon_value=lon_value*2
            lat_value=lat_value*2
            
        #lower left - C
        elif ((lon_value<=-0.5) and (lat_value<=-0.5)):
            square = square + 'C'
    
            lon_value=(lon_value+0.5)*2
            lat_value=(lat_value+0.5)*2

        #lower right - D
        elif ((lon_value>-0.5) and (lat_value<=-0.5)):
            square = square + 'D'
    
            lon_value=lon_value*2
            lat_value=(lat_value+0.5)*2
    
    
    # Q4 - - - - - - - - - - - - - - - - - - - - - - - - - -
    elif ((lon_value<=0) and (lat_value>=0)):
    
        #upper left - A
        if ((lon_value <=-0.5) and (lat_value>=0.5)):
            square = square + 'A'
    
            lon_value=(lon_value+0.5)*2
            lat_value=(lat_value-0.5)*2

        #upper right - B
        elif ((lon_value>-0.5) and (lat_value>=0.5)):
            square = square + 'B'
    
            lon_value=lon_value*2
            lat_value=(lat_value-0.5)*2
            
        #lower left - C
        elif ((lon_value<=-0.5) and (lat_value<0.5)):
            square = square + 'C'
    
            lon_value=(lon_value+0.5)*2
            lat_value=(lat_value)*2

        #lower right - D
        elif ((lon_value>-0.5) and (lat_value<0.5)):
            square = square + 'D'
    
            lon_value=lon_value*2
            lat_value=lat_value*2
    
    
 
    #find square sting length
    length = len(square)
    
    #as long as string length does not meed criteria for depth - continue calculation
    #as an argument the curent square value is sent to the function. This is added in
    #subsequent calculations, and eventually the number for the length of the string
    #equals the number of the depth variable. That's when the job is done.
    if (length < depth):
        #Calculation is recursive - continue the good work
        square = get_recursive_qdgc(lon_value,lat_value,depth,square)
    
    #return value for square
    return square
        
        
#This is where the program is executed
        
def qdgc(feature):
    
    lon_value = feature.getAttribute('lon')
    lat_value = feature.getAttribute('lat')
    qdgc_level = int(feature.getAttribute('qdgc_level'))
    
    lonlatvalues = get_lonlat(lon_value,lat_value)
    
    qdgcvalues = get_recursive_qdgc(lon_value,lat_value,qdgc_level,"")
        
    resultstring = lonlatvalues + qdgcvalues
    
    feature.setAttribute('qdgc',resultstring)
