import arcpy
from arcpy import env

# file resources

f_countries   = ("E:/Dropbox/privat/prosjekter/qdgc/world_countries/ne_110m_admin_0_countries.shp")
f_qdgc        = ("E:/Dropbox/privat/prosjekter/qdgc/world_0_5.shp")


# Tell the system which level of QDGC we are working at

qdgc_level    = 1

# Workspace
env.workspace = "C:/temp"


object_countrys        = "%s" % (f_countries)

countries_list = arcpy.UpdateCursor(object_countrys)


for country_one in countries_list:



	#Retrieve country information

	current_id       = country_one.getValue("FID")
	country_name     = str(country_one.getValue("SUBUNIT"))
	country_code     = str(country_one.getValue("ISO_A3"))
	
	if country_code<>"-99":

		print "Landkode %s" % (country_code)
	
		#Export feature to file
		
		evaluationstring     = "\"FID\" = %s" % (current_id)
		output_country       = "qdgc_%s.shp" % (country_code)
		arcpy.Select_analysis(object_countrys,output_country,evaluationstring)


		output_country_frame = "frame_qdgc_%s.shp" % (country_code)
		arcpy.MinimumBoundingGeometry_management(output_country,output_country_frame,"ENVELOPE", "NONE")
		
		arcpy.Delete_management(output_country)

		#Buffer ramme_:
		
		distanceField = "100000 meters"
		sideType = "FULL"
		endType  = "FLAT"

		output_country_frame_buffer = "buffer_frame_qdgc_%s.shp" % (country_code)
		arcpy.Buffer_analysis(output_country_frame, output_country_frame_buffer, distanceField, sideType, endType)
		
		arcpy.Delete_management(output_country_frame)
		
		#Select fra qdgc basert på ramme one
		
		
		arcpy.MakeFeatureLayer_management(f_qdgc, "fl_qdgc")
		
		arcpy.MakeFeatureLayer_management(output_country_frame_buffer, "fl_countrybuffer")
		
		arcpy.SelectLayerByLocation_management("fl_qdgc","intersect","fl_countrybuffer")
		
		output_qdgc_raw = "qdgc_%s_%s.shp" % (qdgc_level,country_code)
		
		arcpy.CopyFeatures_management("fl_qdgc", output_qdgc_raw)
		
		arcpy.Delete_management("fl_qdgc")
		arcpy.Delete_management("fl_countrybuffer")
		arcpy.Delete_management(output_country_frame_buffer)
		
		#Kjør lonlat2qdgc
		
		#Beregn
		
		#Lagre under navn fra landliste
		
		#Legg til readme.txt
		
		#Pakk sammen (7z)?

#Report finished