require(ggplot2)
require(grid)
require(PBSmapping)
require(plyr)
require(reshape2)

# set working directory 
setwd('..');setwd('..')

# load morpho data
morpho <- read.csv("Other data/Catch data/morpho.csv", header=T, stringsAsFactors = FALSE)
colnames(morpho)[3] <- "SET"

# load catch data for lat long
catch <- read.csv("Other data/Catch data/catch.csv", header=T, stringsAsFactors = FALSE)
catch <- catch[!is.na(catch$CATCH_WEIGHT),]
colnames(catch)[4] <- "SET"

# load echoview log
log <- read.csv("Acoustics/Echoview/Exports/Log/Cruiselog.csv", header=T, stringsAsFactors = FALSE, row.names=1)

# load length weight regression coefficients
coeff_LW <- read.csv("Rscripts/Trawls/LW_coefficients.csv", header=T, stringsAsFactors = FALSE)

# load target strength coefficients
coeff_TS <- read.csv("Rscripts/Trawls/TS_coefficients.csv", header=T, stringsAsFactors = FALSE)



##########################################################################################
##########################################################################################
# data pre-processing



## GET SETS PRESENT IN ECHOVIEW LOG

# get xy data from log
sdlog <- log[grep("SD", log$Region_name, ignore.case=TRUE),] #find SD
sdlog$SET <-  as.numeric(sub("*.SD", "", sdlog$Region_name))
set.xy <- sdlog[c("SET","Lat_s","Lon_s")]

# check --are all the sets present in the echoview log?
sort(unique(as.numeric(sdlog$SET)))
unique(morpho$SET)

# subset morpho and length_only data so that it only contains log sets
morpho <- morpho[morpho$SET %in% unique(as.numeric(sdlog$SET)),]



## SEPERATE WEIGHTS AND LENGTHS THEN JOIN

# get weight records from morpho
weights <- morpho[grep("WEIGHT",morpho$MORPHOMETRICS_ATTRIBUTE_DESC),c(5,8,11,12)]
colnames(weights) <- c("SPECIES_COMMON_NAME", "SPECIMEN_ID", "WEIGHT", "WEIGHT_UNITS")
  
# check weight units
table(weights$WEIGHT_UNITS)

# get length records from morpho
table(morpho$MORPHOMETRICS_ATTRIBUTE_DESC)
lengths <- morpho[grep("LENGTH",morpho$MORPHOMETRICS_ATTRIBUTE_DESC),]

# check length units
table(lengths$MORPHOMETRICS_UNIT_DESC)


# convert all lengths to mm
lengths$SPECIMEN_MORPHOMETRICS_VALUE <- ifelse(lengths$MORPHOMETRICS_UNIT_DESC == "CENTIMETRE", 
                                               lengths$SPECIMEN_MORPHOMETRICS_VALUE*10,
                                               lengths$SPECIMEN_MORPHOMETRICS_VALUE)

# merge lengths and weight data together by specimen, species which has both weights and lengths
morpho <- merge(lengths, weights[c("SPECIMEN_ID", "WEIGHT", "WEIGHT_UNITS")], by = "SPECIMEN_ID", all.x = T)

# get species that don't have weight measurments for each set?
sp_summ <- ddply(morpho, .(SET,SPECIES_COMMON_NAME,MORPHOMETRICS_ATTRIBUTE_DESC), summarise,
                  length = length(SPECIMEN_MORPHOMETRICS_VALUE),
                  weight = length(WEIGHT[!is.na(WEIGHT)]))
sp_summ[!(sp_summ$length == sp_summ$weight),]
no_weights <- sp_summ[sp_summ$weight == 0,]


## CALCULATE WEIGHTS

# subset no weights from morpho data
no_morph <- NULL
for (s in 1:nrow(no_weights)){
df <- morpho[morpho$SET == no_weights$SET[s] & morpho$SPECIES_COMMON_NAME == no_weights$SPECIES_COMMON_NAME[s], ]
no_morph <- rbind(no_morph, df)
}

# remove no_weights subset from morpho data
sub_morph <- morpho[setdiff(rownames(morpho), rownames(no_morph)),]

# check
nrow(no_morph) + nrow(sub_morph) == nrow(morpho)


# merge no_morph with length - weight coefficients
table(no_morph$SPECIES_COMMON_NAME)
table(coeff_LW$SPECIES_COMMON_NAME)
mc <- merge(no_morph, coeff_LW, by = "SPECIES_COMMON_NAME")


# calculate weights (in grams) - only for matching length attributes
for (n in 1:nrow(mc)){
  if(mc$MORPHOMETRICS_ATTRIBUTE_DESC[n] == mc$LENGTH[n]){
    mc$WEIGHT[n] <- mc$a[n] * ((mc$SPECIMEN_MORPHOMETRICS_VALUE[n]*mc$convert[n])/10)^mc$b[n]
    mc$WEIGHT_UNITS[n] <- "GRAM"
  }
}

# bind sub_morph and mc together
rm(morpho)
morpho <- rbind(sub_morph, mc[names(sub_morph)])

#check -- remaining records with NA weight values
table(morpho[is.na(morpho$WEIGHT),]$SPECIES_COMMON_NAME)



## CHECK
# do species lengths in morpho match species length in coeff for regressions?
coeff_TS[!duplicated(coeff_TS$Region_class),c("Region_class", "MORPHOMETRICS_ATTRIBUTE_DESC")]
ddply(morpho, .(SPECIES_COMMON_NAME), summarise, MORPHOMETRICS_ATTRIBUTE_DESC = unique(MORPHOMETRICS_ATTRIBUTE_DESC))








##########################################################################################
##########################################################################################
# Length by species by set


# check mean, sd, and range of lengths within a species
check.lengths <- ddply(morpho, .(SPECIES_COMMON_NAME), summarise, 
                          mean = mean(SPECIMEN_MORPHOMETRICS_VALUE),
                          median = median(SPECIMEN_MORPHOMETRICS_VALUE),
                          n = length(SPECIMEN_MORPHOMETRICS_VALUE),
                          sd = sd(SPECIMEN_MORPHOMETRICS_VALUE),
                          min = min(SPECIMEN_MORPHOMETRICS_VALUE), 
                          max = max(SPECIMEN_MORPHOMETRICS_VALUE))
check.lengths




##########################################################################################
##########################################################################################
# Length Frequency Distribution


# species from echoview analysis regions only
species_full <- unique(log$Region_class[log$Region_type == " Analysis"])
species_full <- gsub( "^\\s+|\\s+$", "" , species_full) # removes leading or trailing whitespace from echoview log
species <- unlist(strsplit(species_full, " "))
species <- unlist(strsplit(species, "-"))

# get lengths for analysis species
length <- NULL
for (i in species){
d <- morpho[grep(i, morpho$SPECIES_COMMON_NAME, ignore.case=T),]
d$SPECIES_COMMON_NAME[grep("rockfish|perch", d$SPECIES_COMMON_NAME, ignore.case=T)] <- "Rockfish"
  length <- rbind(length,d)

}

# species in length table
fish <- unique(length$SPECIES_COMMON_NAME)


##############
# histograms #

for (f in fish){
  
minl <-  min(length$SPECIMEN_MORPHOMETRICS_VALUE[length$SPECIES_COMMON_NAME == f])
maxl <-  max(length$SPECIMEN_MORPHOMETRICS_VALUE[length$SPECIES_COMMON_NAME == f])
meanl <- mean(length$SPECIMEN_MORPHOMETRICS_VALUE[length$SPECIES_COMMON_NAME == f])
name <- gsub( "\\s", "_" , f)
  
histo <-  ggplot(data = length[length$SPECIES_COMMON_NAME == f,]) + 
  geom_histogram(aes(x = SPECIMEN_MORPHOMETRICS_VALUE), binwidth = (maxl-minl)/20) +
  geom_vline(xintercept = meanl, colour = "red") +
  labs(x="Length (mm)", y="Frequency") +
  scale_y_continuous(expand = c(0.01, 0)) +
  # themes
  theme(panel.border = element_rect(fill=NA, colour="black", size = .1),
        panel.background = element_rect(fill="white",colour="white"),
        axis.ticks = element_line(colour="black"),
        axis.ticks.length = unit(0.1,"cm"),
        panel.grid.major = element_blank(),
        panel.grid.minor = element_blank(),
        axis.text = element_text(size=7, colour = "black"),
        axis.title = element_text(size=10, colour = "black"),
        plot.margin = unit(c(.2,.2,.2,.2), "lines"))+ # top, right, bottom, and left
  ggtitle(f)
print(histo)
}


##----------------------------------##
# choose length cut-off for age 1 Hake
cutoff <- 350

##----------------------------------##
# choose length cut-off for Rockfish juvenilles
cutoffrock <- 100



##########################################################################################
##########################################################################################
# MAP mean lengths

# calc mean lengths for each species and each set
mean.lengths <- ddply(morpho, .(SET, SPECIES_COMMON_NAME), summarise, 
                      mean = round(mean(SPECIMEN_MORPHOMETRICS_VALUE)),
                      median = median(SPECIMEN_MORPHOMETRICS_VALUE),
                      sd = sd(SPECIMEN_MORPHOMETRICS_VALUE))
mean.lengths$SPECIES_COMMON_NAME[grep("rockfish|perch", mean.lengths$SPECIES_COMMON_NAME, ignore.case=T)] <- "Rockfish"

# merge lat long with mean lengths
lengths.xy <- merge(mean.lengths, set.xy, by = "SET")


# Regional Polygon 
data(nepacLLhigh)
landT<- thinPolys(nepacLLhigh, tol = 0, filter = 15)
landC <- clipPolys(landT, xlim = c(min(set.xy$Lon_s)-2, max(set.xy$Lon_s)+2), 
                   ylim = c(min(set.xy$Lat_s)-2, max(set.xy$Lat_s)+2))
land <- data.frame(landC)


#####################
# Map mean lengths #

for (f in fish){

name <- gsub( "\\s", "_" , f)
fish.xy <- lengths.xy[lengths.xy$SPECIES_COMMON_NAME == f,]

mapmean <-  ggplot(data = NULL) + 
  # land polygon  
  geom_polygon(data = land, aes_string(x = "X", y = "Y", group="PID"), 
               fill = "gray80", colour = "gray60", size = .1) +
  # trawl points
  geom_point(data = fish.xy, aes(x = Lon_s, y = Lat_s, size = mean), 
             colour = "#e41a1c" ,pch=21)+
  geom_point(data = fish.xy, aes(x = Lon_s, y = Lat_s, size = mean), 
             colour = "#e41a1c" ,pch=21, fill = "#e41a1c" , alpha =.3)+
  scale_size_area(max_size = 8, name = " Mean\n Length (mm)") +
  # spatial extent
  coord_map(xlim = c(min(set.xy$Lon_s)-2, max(set.xy$Lon_s)+2), 
            ylim = c(min(set.xy$Lat_s)-1, max(set.xy$Lat_s)+1)) +
  # labs
  labs(x="Longitude", y="Latitude") +
  # themes
  theme(panel.border = element_rect(fill=NA, colour="black", size = .1),
        panel.background = element_rect(fill="white",colour="white"),
        axis.ticks = element_line(colour="black"),
        axis.ticks.length = unit(0.1,"cm"),
        panel.grid.major = element_blank(),
        panel.grid.minor = element_blank(),
        axis.text = element_text(size=7, colour = "black"),
        axis.title = element_text(size=9, colour = "black"),
        legend.text = element_text(size=8),
        legend.title = element_text(size=9, face="plain"),
        legend.key = element_blank(),
        legend.position = "right",
        plot.margin = unit(c(.5,.5,.5,.5), "lines")) +
  ggtitle(lab = name)
print(mapmean)
}




##########################################################################################
##########################################################################################
# EXPORT mean length and weight by species

# group catch data
catch <- ddply(catch, .(SET, SPECIES_COMMON_NAME), summarise, CATCH_WEIGHT = sum(CATCH_WEIGHT))

# group rockfish catch together
rock <- grep("rockfish|perch", catch$SPECIES_COMMON_NAME, ignore.case=T)
r_catch <- catch[rock,c("SET", "SPECIES_COMMON_NAME", "CATCH_WEIGHT")]
rs_catch <- ddply(r_catch, .(SET), transform, CATCH_WEIGHT = sum(CATCH_WEIGHT))

# group salmon catch together
salmon <- grep("COHO SALMON|CHUM SALMON|CHINOOK SALMON|PINK SALMON|SOCKEYE SALMON", catch$SPECIES_COMMON_NAME, ignore.case=T)
s_catch <- catch[salmon,c("SET", "SPECIES_COMMON_NAME", "CATCH_WEIGHT")]
ss_catch <- ddply(s_catch, .(SET), transform, CATCH_WEIGHT = sum(CATCH_WEIGHT))


# group myctophid catch together
myctophid <- grep("myctophid|lampfish|headlight", catch$SPECIES_COMMON_NAME, ignore.case=T)
m_catch <- catch[myctophid,c("SET", "SPECIES_COMMON_NAME", "CATCH_WEIGHT")]
sm_catch <- ddply(m_catch, .(SET), transform, CATCH_WEIGHT = sum(CATCH_WEIGHT))


w_catch <- catch[-c(rock,salmon,myctophid),c("SET", "SPECIES_COMMON_NAME", "CATCH_WEIGHT")]
grp_catch <- rbind(w_catch,rs_catch, ss_catch, sm_catch)

# merge catch and morpho
comb <- merge(morpho, grp_catch[c("SET", "SPECIES_COMMON_NAME", "CATCH_WEIGHT")], 
              by = c("SET", "SPECIES_COMMON_NAME"))


# compare morpho species to analysis species
species_full
unique(comb$SPECIES_COMMON_NAME)

# rockfish species
rockfishsp <- unique(grep("rockfish|perch", comb$SPECIES_COMMON_NAME, ignore.case=T, value = T))


# reclassify morpho species to fit analysis region species
comb$SPECIES_COMMON_NAME[comb$SPECIES_COMMON_NAME == "PACIFIC HAKE" & 
                    comb$SPECIMEN_MORPHOMETRICS_VALUE > cutoff  ] <- "Hake"
comb$SPECIES_COMMON_NAME[comb$SPECIES_COMMON_NAME == "PACIFIC HAKE" & 
                    comb$SPECIMEN_MORPHOMETRICS_VALUE <= cutoff  ] <- "Age-1 Hake"
comb$SPECIES_COMMON_NAME[comb$SPECIES_COMMON_NAME %in% rockfishsp & 
                           comb$SPECIMEN_MORPHOMETRICS_VALUE <= cutoffrock  ] <- "JuvenileRockfish"
comb$SPECIES_COMMON_NAME[comb$SPECIES_COMMON_NAME %in% rockfishsp & 
                           comb$SPECIMEN_MORPHOMETRICS_VALUE > cutoffrock  ] <- "Rockfish"
comb$SPECIES_COMMON_NAME[grep("herring", comb$SPECIES_COMMON_NAME, ignore.case=T)] <- "Herring"
comb$SPECIES_COMMON_NAME[grep("myctophid|lampfish|headlight", comb$SPECIES_COMMON_NAME, ignore.case=T)] <- "Myctophids"
comb$SPECIES_COMMON_NAME[grep("cps", comb$SPECIES_COMMON_NAME, ignore.case=T)] <- "CPS"
comb$SPECIES_COMMON_NAME[grep("sardine", comb$SPECIES_COMMON_NAME, ignore.case=T)] <- "Sardine"
comb$SPECIES_COMMON_NAME[grep("mackerel", comb$SPECIES_COMMON_NAME, ignore.case=T)] <- "Mackerel"
comb$SPECIES_COMMON_NAME[grep("pollock", comb$SPECIES_COMMON_NAME, ignore.case=T)] <- "Pollock"
comb$SPECIES_COMMON_NAME[grep("eulachon", comb$SPECIES_COMMON_NAME, ignore.case=T)] <- "Eulachon"
comb$SPECIES_COMMON_NAME[grep("salmon", comb$SPECIES_COMMON_NAME, ignore.case=T)] <- "Salmon"

# check species
table(comb$SPECIES_COMMON_NAME)

# check weight units - should be all in grams
table(comb$WEIGHT_UNITS)

# add strata
comb <- merge(comb, set.xy, by = "SET", all.x=T)
comb$strata <- 1
comb$strata[comb$Lat_s >= 50] <- 2
comb$strata[comb$Lat_s >= 52] <- 3


# calc mean length and weight for each species
morph_sum <- ddply(comb, .(strata, SPECIES_COMMON_NAME), summarise, 
                      mean.length.mm = mean(SPECIMEN_MORPHOMETRICS_VALUE),
                      weigted.mean.length.mm = sum(SPECIMEN_MORPHOMETRICS_VALUE * CATCH_WEIGHT, 
                                                   na.rm=T)/sum(CATCH_WEIGHT, na.rm=T),
                      mean.weight.kg = mean(WEIGHT, na.rm=T)/1000,
                      n = length(WEIGHT))
morph_sum

# export
write.csv(morph_sum, file = "Other data/Catch data/morpho_summary.csv")



##########################################################################################
##########################################################################################
# EXPORT mean length, weight and counts by species by set


# partition hake and age1 hake CATCH_WEIGHT based on individual weights
comb$phake <- 1
for (h in unique(comb$SET)){
  a1 <- comb$WEIGHT[comb$SPECIES_COMMON_NAME == "Age-1 Hake" & comb$SET == h]
  ad <- comb$WEIGHT[comb$SPECIES_COMMON_NAME == "Hake" & comb$SET == h]
  ma1 <- mean(a1, na.rm=T) * length(a1)
  ma1 <- ifelse(is.na(ma1),0,ma1)
  mad <- mean(ad, na.rm=T) * length(ad)
  mad <- ifelse(is.na(mad),0,mad)
  pa1 <-  ma1/(ma1+mad)
  pad <- 1 - pa1
  comb$phake[comb$SPECIES_COMMON_NAME == "Age-1 Hake" & comb$SET == h] <- pa1
  comb$phake[comb$SPECIES_COMMON_NAME == "Hake" & comb$SET == h] <- pad
}


# calculate new total catch weights for hake and age1 hake in the same tows
comb$CATCH_WEIGHT <- comb$CATCH_WEIGHT * comb$phake



# calc mean weights (in kg) for each species and each set
morph_count <- ddply(comb, .(SET, SPECIES_COMMON_NAME, strata), summarise,
                     mean.length.mm = mean(SPECIMEN_MORPHOMETRICS_VALUE),
                     mean.weight.kg = mean(WEIGHT, na.rm=T)/1000,
                     total.weight.kg = min(CATCH_WEIGHT))

# merge catch and mean length data
morph_count$Estimated_N <- round(morph_count$total.weight.kg/morph_count$mean.weight.kg)
morph_count


# export summary
write.csv(morph_count, file = "Other data/Catch data/morpho_counts.csv")




##########################################################################################
##########################################################################################
# EXPORT length frequencies by species


# calc length freq 
freqtable <- ddply(comb, .(SPECIMEN_MORPHOMETRICS_VALUE, SPECIES_COMMON_NAME, SET, strata),
                   summarise,
                   Freq = length(SPECIMEN_MORPHOMETRICS_VALUE))


# export summary
write.csv(freqtable, file = "Other data/Catch data/Length_freq.csv")







