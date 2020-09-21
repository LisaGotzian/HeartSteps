#---------- Extract meaningful data from heartsteps ----------
#
# Goal: unite the data that is there into a meaningful dataset to
#       run stan estimations with it

# Data: The data consists of 37 participants that received 2-5 notifications
# per day and the corresponding steps they took every day. Additionally,
# the data features global variables like personality factors collected in
# the beginning and daily EMAs. The hope is to improve particpants' steps
# by intervening.
#
#
# Lisa Gotzian, July 9, 2020

#------------------------ The Github approach -----------------
# Following the team's documentation on Github,
# https://github.com/StatisticalReinforcementLearningLab/HeartstepsV1Code/
# I read in the following .RData-Files:

load("csv.RData")
# documentation here:
# https://github.com/StatisticalReinforcementLearningLab/HeartstepsV1Code/wiki/B-CSV-files

load("analysis.RData")
# documentation here: 
# https://github.com/StatisticalReinforcementLearningLab/HeartstepsV1Code/wiki/C-Analysis-data-frames


## Nick's primary dataframe for comparison later
analysis.data <- function(days = 0:35, max.day = 41) {
  ids  <- unique(suggest$user[suggest$study.day.nogap == rev(days)[1] &
                                !is.na(suggest$study.day.nogap)])
  d <- subset(suggest, !is.na(study.day.nogap) & user %in% ids & 
                !(avail == F & send == T) & study.day.nogap <= max.day &
                !is.na(send.active),
              select = c(user, study.day.nogap, decision.index.nogap, decision.utime,
                         slot, study.date, intake.date, intake.utime, intake.slot,
                         travel.start, travel.end, exit.date, dropout.date,
                         last.date, last.utime, last.slot, recognized.activity,
                         avail, connect, send, send.active, send.sedentary, jbsteps10, 
                         jbsteps10.zero, jbsteps10.log, jbsteps30pre,
                         jbsteps30, jbsteps30pre.zero, jbsteps30.zero, 
                         jbsteps30pre.log, jbsteps30.log, jbsteps60pre,
                         jbsteps60, jbsteps60pre.zero, jbsteps60.zero, 
                         jbsteps60pre.log, jbsteps60.log, response, location.category, jbmins120, jbmins90))
  return(list(data = d, ids = ids))
}
days <- 0:35
primary <- analysis.data(days = days)
ids     <- primary$ids
primary <- primary$data

#---------------------------- Preliminaries -----------------
library(lubridate)
library(readr)
library(magrittr)
library(dplyr)

### Helper function to get all column names for documentation
#cat(paste(colnames(suggest), collapse = "\n"))

### Prelimaries as documented in init.R
## largest number of digits used to represent fractional seconds
options(digits.secs = 6)

## number of digits in Unix time (seconds since 1970-01-01 00:00 UTC)
## + largest number of digits used to represent fractional seconds
options(digits = 10 + 6)

sys.var <- switch(Sys.info()["sysname"],
                  "Windows" = list(locale = "English",
                                   mbox = "Z:/HeartSteps/"),
                  "Darwin" = list(locale = "en_US",
                                  mbox = "/Volumes/dav/HeartSteps/"),
                  "Linux" = list(locale = "en_US.UTF-8",
                                 mbox = "~/mbox/HeartSteps/"))
## time zone identifiers are localized, so set the locale
Sys.setlocale("LC_ALL", sys.var$locale)

## arithmetic on POSIXct objects uses system time zone, so set this to UTC
Sys.setenv(TZ = "GMT")

#---------------------- 1. The users dataframe ------------------------
# 44 observations, the dataframe with the lowest timeframe - once per user

#---------------------- 1.1 Working with the rows -------------------
# throwing out users that didn't participate
users <- users[!users$exclude,]
#... # 37 observations when excluding users


#----------------------- 1.2 Working with the data ---------------------
# exitdate will be kept, exit.date will be removed. After considering where they
# differ and comparing with the last recorded steps and the last notification, 
# exitdate seemed to be more accurate.
# only one case (last notif: 12/08, last steps: 12/08, exit.date: 12/09,
# exitdate: 12/03) seems to be incorrect for exitdate:
users[users$user == 25, "exitdate"] <- users[users$user == 25, "exit.date"]
# However then we don't know the exittime and give it NA:
users[users$user == 25, "exittime"] <- NA

# generic exit survey times for NAs and those that don't have a ":" time format
users[is.na(users$exittime),"exittime"] <- "12:00pm"
users[!grepl(":", users$exittime), "exittime"] <- "12:00pm"


#------------------------- 1.2.a) userindex -----------------------------
# the following will be first part of the final users dataframe, hence we
# collect them in "userindex"
userindex <- with(users,
                  data.frame(user.index, userid,
                            ### first points in time according to the dataframes:
                            # from users.csv
                            intake.survey.utime = intake.utime,
                            intake.survey.tz = intake.tz,
                            intake.survey.gmtoff = intake.gmtoff))

# from dailyema.csv
#first.ema.response.utime will be added after having dealt with daily
userindex$first.ema.response.utime <- NA

# from suggest.csv
userindex$first.notif.utime <- as.POSIXct(tapply(suggest$decision.utime,
                                                 suggest$user, min, na.rm=T),
                                          origin = "1970-01-01 00:00.00 UTC")

# from steps.csv
userindex$first.steps.utime <- as.POSIXct(tapply(jbslot$start.datetime, jbslot$user, min))


### last points in time according to the dataframes:
# from users.csv: exit survey date in utime
userindex$exit.survey.utime <- date(users$exitdate) +
  hms(parse_time(users$exittime, "%I:%M%p"))+users$last.gmtoff

# infer timezone by last notification timezone
userindex$exit.survey.tz <- users$last.tz
userindex$exit.survey.gmtoff <- users$last.gmtoff

# from dailyema.csv
# last.ema.response.utime will be added after having dealt with daily
userindex$last.ema.response.utime <- NA

# from dailyema.csv or suggest.csv
userindex$last.notif.utime <- users$last.utime

# from steps.csv
userindex$last.steps.utime <-  as.POSIXct(tapply(jbslot$start.datetime,
                                                 jbslot$user, max))

userindex <- cbind.data.frame(userindex,
                              subset(users, select = c(
                                travel.start, travel.end, dropout.date)))

# total days: take the minimum of either...
userindex$totaldays <- as.numeric(round(
  with(userindex,
       pmin(last.steps.utime-first.steps.utime, # steps recorded or
            exit.survey.utime-intake.survey.utime, # intake to exit survey or
            as.POSIXct(dropout.date)-first.steps.utime, # steps till dropout
            na.rm=T))))
# total days minus potential travel days
traveldays <- userindex$travel.end-userindex$travel.start
userindex$totaldays <- ifelse(is.na(traveldays),
               userindex$totaldays, userindex$totaldays-traveldays)


#----------------------- 1.2.b) usermiddle ------------------------
# The survey section is the middle part of the users dataframe,
# hence "usersmiddle"
usersmiddle <- cbind.data.frame(
  subset(users, select = c(own.phone, age:compcomfort)),
  
  with(users,
                  data.frame(office.shops = shopsoffice,
                             office.pleasant = pleasantoffice,
                             office.sidewalk = sidewalkoffice,
                             consc.detail = detail,
                             consc.prepared = prepared,
                             consc.carryplans = carryplans,
                             consc.startwork = startwork,
                             consc.wastetime = wastetime,
                             consc.duties = duties,
                             consc.makeplans = makeplans,
                             consc = conscientious)),
  
  subset(users, select = c(stairs.intake:stand.intake,
                                         stairs.exit:stand.exit,
                                         selfeff.tired.intake:selfeff.precip.intake,
                                         selfeff.intake,
                                         selfeff.tired.exit:selfeff.precip.exit,
                                         selfeff.exit,
                                         house:placeshome)))


#----------------------- 1.2.c) useripaq ------------------------
# The IPAQ questionnaire, the last part of the final users dataframe,
# hence "useripaq"

## For intake:
useripaq <- subset(users, select = c(vigact.days.intake, modact.days.intake,
                                     walk10.days.intake))

# Calculating total sitting time intake
useripaq$sit.time.intake <- users$sit.hrs.intake * 60 + users$sit.min.intake

useripaq <- cbind.data.frame(
  useripaq,
  subset(users, select = c(vigact.time.intake:walk.time.intake,
                           vigact.metmins.intake:metmins.intake)))

# Correcting for the ipaq score and assigning it to levels 1-3
# for intake survey
useripaq$ipaq.hepa.intake <-  as.numeric(users$ipaq.hepa.intake)*2+ # highest level
  as.numeric(users$ipaq.minimal.intake)+ # medium level
  1


## For exit: 
# Keep the days as they are, the hrs and min are not kept
useripaq$vigact.days.exit <- users$vigact.days.exit
useripaq$modact.days.exit <- users$modact.days.exit
useripaq$walk10.days.exit <- users$walk10.days.exit

# Calculating total sitting time exit
useripaq$sit.time.exit <- users$sit.hrs.exit * 60 + users$sit.min.exit

useripaq <- cbind.data.frame(
  useripaq,
  subset(users, select = c(vigact.time.exit:walk.time.exit,
                           vigact.metmins.exit:metmins.exit)))


# Correcting for the ipaq score and assigning it to levels 1-3
# for exit survey
useripaq$ipaq.hepa.exit <-  as.numeric(users$ipaq.hepa.exit)*2+ # highest level
  as.numeric(users$ipaq.minimal.exit)+ # medium level
  1


### All thrown out columns are documented in the appendix.

#------------------- 2. The dailyema dataframe -------------------
# 1686 observations - daily data per user

### 1. Working with the rows 
# nothing to report

#---------------------- 2.2 Working with the data ----------------
### anonymize front.end.application
anonymizeTest <- daily$front.end.application== "com.kathleenOswald.solitaireGooglePlay"
anonymizeTest <- ifelse(is.na(anonymizeTest), FALSE, anonymizeTest)
daily[anonymizeTest, "front.end.application"] <- "com.solitaireGooglePlay"


#----------------------- 2.2.a) dailyindex ------------------------
# First part of daily is collected in dailyindex
daily$ema.index <- 1:nrow(daily)

dailyindex <- subset(daily,
                     select = c(user.index, ema.index, study.date,
                                study.day, study.day.nogap, weekday, travel))
# FIXME what is ltime? seems to be before the notification

# add a POSIXct column for the selected notification time
dailyindex$ema.select.utime <- with(daily, as.POSIXct(study.date) + ema.hours * 60^2 -
                                      ema.gmtoff)
dailyindex$ema.select.updated <- daily$date.updated

### when was the EMA notification sent?
# This column is missing, hence it is added to dailyindex 
ema.notif.utime <- inner_join(daily, notify,
                                         by = c("user", "study.date" = "ema.date")) %>%
  select("user", "study.date", "notified.utime") %>%
  right_join(., daily, by = c("user", "study.date")) %>% # join them with daily
  arrange(user, study.date) %>% select(notified.utime)

dailyindex$ema.notif.utime <- ema.notif.utime$notified.utime
dailyindex$ema.notif.imput.utime <- daily$ema.utime
dailyindex$ema.notif.imput.tz <- daily$ema.tz
dailyindex$ema.notif.imput.gmtoff <- daily$ema.gmtoff

### when did participants respond to the EMA?
# This column is missing, hence it is added to daily
ema$ema.response.utime <- ema$utime.stamp
ema$ema.response.tz <- ema$tz
ema$ema.response.gmtoff <- ema$gmtoff



#----------------------- 2.2.b) dailytimes ------------------------
# The timestamps are going to be collected in "dailytimes"...
dailytimes <- inner_join(daily, ema,
                         by = c("user", "study.date" = "notified.date")) %>%
  select("user", "study.date",
         "ema.response.utime", "ema.response.tz", "ema.response.gmtoff") %>%
  group_by(user, study.date) %>% # group by identifiers
  mutate(ema.response.utime = max(ema.response.utime)) %>% # keeping only the last engagement
  distinct()%>% ungroup() %>% 
  right_join(., daily, by = c("user", "study.date")) %>%
  arrange(user, study.date) %>%
  select("ema.response.utime", "ema.response.tz", "ema.response.gmtoff")

#... and "dailytimes2"
dailytimes2 <- with(daily,
                    data.frame(ema.device.utime = device.utime,
                              ema.device.since = device.since,
                              interaction.count,
                              connect, notify, view, respond))



#----------------------- 2.2.c) dailymiddle ------------------------
# The last part of daily is collected in "dailymiddle"
dailymiddle <- cbind.data.frame(
  subset(daily, select = c(recognized.activity:snow, 
                                        planning, planning.today)),
  with(daily,
       data.frame(planning.response = response)),
  
  subset(daily, select = c(follow, ema.set.length:typical,
                           energetic, urge,
                           active.cardio:active.none,
                           down.motivate:enabler.other,
                           jbsteps.direct:app.secs.all))
  )

# throw out GPS
dailymiddle <- dailymiddle %>% select(-gps.coordinate, -home, -work)


### Exkurs: Planning & planning.today
# planning is the categorized planning.response, however it doesn't seem
# to be read in correctly. planning.today is yesterday's planning response.
# They don't add up:
planning <- NA
planning <- c(planning, dailyema$planning) 

planning.today <- dailyema$planning.today
planning.today <- c(planning.today, NA)

sum(!planning == planning.today, na.rm=T)
sum(!dailyema$planning == dailyema$planning.today, na.rm=T)


# That's why I decide to re-categorize the columns by hand.
changeplans <- with(dailyema,
                    cbind(user.index, study.day, planning, planning.today,
                          planning.response, connect
                    ))
#write.csv(changeplans, file = "changeplans.csv")

changeplans <- read.csv2("changeplans.csv", na.strings = "")

# Now, I only need to add disconnected and no_planning
changeplans[!changeplans$connect, "planning.new"] <- "disconnected"
changeplans[is.na(changeplans$planning.new), "planning.new"] <- "no_planning"

# and add it to planning.today.new
changeplans$planning.today.new <- c("no_planning",
                                    changeplans[-1686, "planning.new"])

dailymiddle$planning <- changeplans$planning.new
dailymiddle$planning.today <- changeplans$planning.today.new

#------------------ 3. The suggestions dataframe ---------------
# 2-5 times per day per user, 8274 rows

# This dataframe had many possibly confusing columns, hence a
# short summary of these columns before we begin:
## Basic status
# connect is 735 false, 7539 true
# is.randomized: 3070 false, 4469 true, 735 NA

## Availability
# snooze.status: 7496 false, 43 true, 735 NA
# intransit: 6628 false, 911 true, 735 NA
#   911 are augmented_vehicle, in_vehicle, on_bicycle or on_foot
#   as recognized by recognized.activity

# avail:  1684 false, 6590 true
#   connect (7539) & !snooze (7496) & !intransit (6628) = avail (6590)

# is.prefetch: 6380 false, 709 true, 735 NA
# -> if user is not connected to server at notification, the
# context information is for 30 min prior

# don't know what to do with link and link is nowhere explained.
# link: 4519 false, 3020 true, 735 NA

#--------------------- 3.1 Working with the rows--------------------
## Correcting for notifications
# notify: 3265 false, 4274 true, 735 NA -> if phone was not connected or not
# connected 30 min prior to the decision, no notification (735 cases)
# returned message corresponds to this: 4274 cases, 3265 donotnotify, 735 NA

# However, when prefetch was true, notify was always true, previous analyses
# have corrected for it by creating "send":
# send: 4536 false, 3918 true 
#   random (4469) & avail (6590) = send (...)
# turns out: in 356 cases, notify was corrected in send and there wasn't
# actually a notification sent.
# in 1 case, notify was false but send was already true as there was a
# response recorded.
# todo -> throw out notify, adjust returned.message to send, adjust send with NAs

suggest[!is.na(suggest$returned.message) & !suggest$send,
        "returned.message"] <- "donotnotify"
suggest[!suggest$connect,"send"] <- NA


# returned message now is: 3917 cases, 3622 donotnotify, 735 NA
# send now is: 3621 false, 3918 true, 735 NA

#----------------------- 3.2 Working with the data --------------------#
#----------------------- 3.2.a) suggesttimes ------------------------
# Time and general variables, the first part of the suggest dataframe,
# hence "suggesttimes"

suggesttimes <- cbind.data.frame(
  subset(suggest, select = c(user.index, study.date,
                                           decision.index, decision.index.nogap)),
  
  with(suggest,
       data.frame(sugg.select.utime = slot.utime,
                  sugg.select.slot = slot,
                  sugg.select.update = date.updated,
                  sugg.tz = tz, sugg.gmtoff = gmtoff,
                  sugg.decision.utime = decision.utime,
                  sugg.decision.slot = time.stamp.slot,
                  sugg.context.utime = utime.stamp,
                  sugg.response.utime = responded.utime,
                  sugg.device.utime = device.utime, 
                  sugg.device.since = device.since,
                  interaction.count)))

## Add the EMA index, join and select in the correct order
# throw out study.date as emaindex serves as identifier now
suggesttimes <- left_join(suggesttimes, dailyindex,
                               by = c("study.date", "user.index")) %>%
  select(user.index, ema.index, colnames(suggesttimes), -study.date)



# -------- Exkurs: A few notes on the decisions in 2.a)------------
# and why certain columns didn't make it into the final dataset

# Proof 1: slot.utime is the same as hrsmin + gmtoff,
# just including the study day, hence it is redundant:
with(suggest,
     sum(!hour(slot.utime+gmtoff) == 
           hour(hm(hrsmin)), na.rm=T))

with(suggest,
     sum(!minute(slot.utime) == 
           minute(hm(hrsmin)), na.rm=T))

# Proof 2: time.slot is only the names of the slots
# and is inaccurate, hence it is redundant:
table(suggest$time.stamp.slot)
table(suggest$slot)
table(suggest$time.slot)

# Proof 3: notified.utime and notification.message only lists the times
# the user responded, not all cases a notification is sent:
sum(is.na(suggest$notified.utime)) # 5253 NAs
sum(is.na(suggest$responded.utime)) # 5253 NAs
sum(is.na(suggest$notification.message)) # 5253 NAs

# other than that, it is the same as the context time (utime.stamp) (!),
# and doesn't correspond to the actual notification time unfortunately:

# with a 5-sec allowed delay, only in 3 cases a different time
decnotifdiff <- suggest$utime.stamp-suggest$notified.utime
sum((decnotifdiff)>5, na.rm=T)

# after 6, 22 and 31 minutes
table(round(decnotifdiff[decnotifdiff>5]/60))

# I cannot make sense of a variable that is essentially the same as another
# (but with more NA!) and has 3 different time points that don't seem to
# follow a pattern when it differs.
# I therefore take decision.utime as the notification and discard
# notified.utime

#----------------------- 3.2.b) suggestavail ------------------------
# Availability, notification and context variables are collected in
# "suggestavail"
suggestavail <- cbind.data.frame(
  subset(suggest, select = c(connect, is.randomized,
                             snooze.status, intransit, avail,
                             send,
                             send.active, send.sedentary,
                             is.prefetch,
                             
                             recognized.activity,recognized.activity.response,
                             tag.active, tag.indoor, tag.outdoor,
                             tag.outdoor_snow,
                             front.end.application,
                             returned.message, 
                             response)),
  
  rename_all(subset(suggest, select = c(city:snow)),
                  function(x) paste0("dec.", x) # add a prefix "dec."
                  ), 
  
  rename_all(subset(suggest, select = c(city.response:snow.response)),
                  function(x) paste0("response.", gsub(".response","",x))
                  # move the suffix ".response" to the front as "response."
                  )
)

#----------------------- 3.2.c) suggeststeps ------------------------
# The aggregate steps are collected in "suggestteps"

# How many NAs are there per user?
tapply(suggest[is.na(suggest$jbsteps30),"user"],
       suggest[is.na(suggest$jbsteps30),"user"], length)

# Removing the spline imputation
# I don't think the spline imputation does such a good job if there
# are NAs for users. It's not important to have a value but to have 
# a pattern of 0 or 1 - walking or not walking. Spline can't do that:
# I'll throw out all ".spl" columns.
plot(suggest[suggest$user == 1, "jbsteps30"])
plot(suggest[suggest$user == 1, "jbsteps30.spl"])
plot(suggest[suggest$user == 25, "jbsteps30"])
plot(suggest[suggest$user == 25, "jbsteps30.spl"])
plot(suggest[suggest$user == 39, "jbsteps30"])
plot(suggest[suggest$user == 39, "jbsteps30.spl"])


suggeststeps <- suggest %>% select(starts_with("jb"), starts_with("gf"),
                                   -ends_with("spl"),
                                   # throw out log-transforms, you shouldn't
                                   # log-transform count data.
                                   # https://www.r-bloggers.com/do-not-log-transform-count-data-bitches/
                                   -ends_with("log"))


# All thrown out columns documented in the appendix!


#--------------------- 4. The steps dataframe ------------------------
# minute-by-minute data, approx. 200,000 rows per user.
# gf is google fitbit data, jb is jawbone data.

### 4.1 Working with the rows
# An error from merging:
jbslot <- subset(jbslot, !is.na(slot))
jbslotpre <- subset(jbslotpre, !is.na(slot))
gfslot <- subset(gfslot, !is.na(slot))
gfslotpre <- subset(gfslotpre, !is.na(slot))

#------------------- 4.2 Working with the columns-------------------
# This section will throw out end-times, and redundant start-times
# as well as redundant columns from other dataframes

### Throw out end-times
# start-times are the minute steps were recorded
# end-times are 
#           a) the end of the minute for jb
#           b) the start of the next minute for gf
# sampling rates remain the same = 1min

# proving a)
diff <- as.numeric(jbslot$end.utime-jbslot$start.utime)
table(diff)

# proving b): endtime-starttime is approx. the same as starttime lag 1
diff <- as.numeric(gfslot$end.utime-gfslot$start.utime)
hist(diff, breaks = 5000, xlim = c(0,80))
diff <- as.numeric(diff(gfslot$start.utime, lag = 1))
hist(diff, breaks = 1000000, xlim = c(0,80))
# -> hence we throw out the end.times as they are 1) different and 2) not very
# meaningful if we know start.utime

### start.udate, start.date are the same plus already in start.utime
# start.datetime is the same as start.utime
# Proof:
checkStartDate <- function(df){
  df$start.datetime <- as.POSIXct(df$start.datetime)

  # Does it differ in any case? Should be all 0!
  cat(sum(!df$start.utime == df$start.datetime, na.rm =T))
  cat(sum(!date(df$start.utime) == df$start.udate, na.rm =T))
  cat(sum(!date(df$start.utime) == df$start.date, na.rm =T))
  
  # If we remove NAs by na.rm in sum, are there NAs we have to consider?
  cat(sum(is.na(df$start.datetime)))
  cat(sum(is.na(df$start.utime)))
  cat(sum(is.na(df$start.udate)))
  cat(sum(is.na(df$start.date)))
}

sapply(list(gfslot, gfslotpre, jbslot, jbslotpre), checkStartDate)
# start.udate and start.datetime can be thrown out. The 45.000s are
# for start.date.

# start.date that is different from date(start.utime) for jbslot and jbslotpre
# in approx. 45.000 cases. Why? It is the *local* start date:
sum(!date(jbslot$start.utime.local) == date(jbslot$start.date), na.rm =T)

# -> Hence, I can remove start.udate, start.datetime and also start.date


### Remove all redundant columns
removeColForSteps <- function(df){
  df1 <- df %>% select(
    # from users.csv
    -user, -intake.date, -intake.utime, -intake.tz,
    -intake.gmtoff, -intake.hour, -intake.min, -intake.slot,
    -travel.start, -travel.end,
    -exit.date, -dropout.date, -last.date, -last.utime, -last.tz,
    -last.gmtoff, -last.hour, -last.min,
    -userid,
    
    # from dailyema.csv
    -study.day, -decision.utime,
    
    # from suggest.csv
    -connect, -avail, -send,
    
    # redundant columns, see proof
    -end.datetime, -end.utime, -end.udate, -end.date,
    # timezone is always UTC and doesn't give more information
    -timezone, -tz, -gmtoff,
    # start.udate, start.date and start.datetime are the same
    # as start.utime/start.utime.local
    -start.udate, -start.date, -start.datetime
  )
  return(df1)
}

gfslot1 <- removeColForSteps(gfslot)
gfslotpre1 <- removeColForSteps(gfslotpre)

jbslot1 <- removeColForSteps(jbslot)
jbslotpre1 <- removeColForSteps(jbslotpre)

# also delete redundant column end.utime.local that's only in jbslot
jbslot1$end.utime.local <- NULL
jbslotpre1$end.utime.local <- NULL
jbslot1$decision.index.nogap <- NULL
jbslotpre1$decision.index.nogap <- NULL

#----------------------- 4.2.a) jbsteps ------------------------
### Compare the jbslot & jbslotpre
## Jawbone data
# merging by start.utime, user.index, steps  shows:
# start.utime, user.index and steps are all the same.
# the two dataframes only differ in the step's allocation to slots.
jbsteps <- full_join(jbslot1, jbslotpre1,
                     by = c("user.index", "start.utime", "steps",
                            "start.utime.local"), suffix = c("", ".following.dec"))

# the steps are (almost) all allocated to different slots:
sum(jbsteps$decision.index == jbsteps$decision.index.following.dec, na.rm=T)
sum(jbsteps$slot == jbsteps$slot.following.dec, na.rm=T)

# The first/last steps that have been walked are partly slots:
sum(is.na(jbsteps$slot)) # 772 minutes over all users before the first notif
sum(is.na(jbsteps$slot.following.dec)) # 2421 minutes after the last notif

### Reorder columns
jbsteps <- with(jbsteps,
                data.frame(user.index, #emaindex,
                           study.date,
                           steps.utime = start.utime,
                           steps.utime.local = start.utime.local,
                           steps,
                           decision.index, slot, study.day.nogap,
                           decision.index.following.dec, slot.following.dec,
                           study.day.nogap.following.dec))

### Add the EMA index, join and select in the correct order
# throw out study.date as emaindex serves as identifier now
jbsteps <- left_join(jbsteps, dailyindex,
                       by = c("user.index", "study.date"),
                       suffix = c("", "daily")) %>%
  select(user.index, ema.index, colnames(jbsteps), -study.date) %>%
  arrange(user.index, steps.utime)

#----------------------- 4.2.b) gfsteps ------------------------
# Compare gfslot & gfslotpre
## Google Fit
gfsteps <- full_join(gfslot1, gfslotpre1,
                     by = c("user.index", "start.utime", "steps"),
                     suffix = c("", ".following.dec"))

# the steps are all allocated to different slots:
sum(gfsteps$decision.index == gfsteps$decision.index.following.dec, na.rm=T)
sum(gfsteps$slot == gfsteps$slot.following.dec, na.rm=T)

# The first/last steps that have been walked are partly slots:
sum(is.na(gfsteps$slot)) # 790 minutes over all users before the first notif
sum(is.na(gfsteps$slot.following.dec)) # 9714 minutes after the last notif


# Reorder columns
gfsteps <- with(gfsteps,
                data.frame(user.index, #emaindex,
                           steps.utime = start.utime,
                           study.date, steps,
                           decision.index, slot,
                           decision.index.following.dec, slot.following.dec))

### Add the EMA index, join and select in the correct order
# throw out study.date as emaindex serves as identifier now
gfsteps <- left_join(gfsteps, dailyindex,
                       by = c("user.index", "study.date"),
                       suffix = c("", "daily")) %>%
  select(user.index, ema.index, colnames(gfsteps), -study.date) %>%
  arrange(user.index, steps.utime)

#--------------------------- Merging dataframes ---------------------
userfinal <- cbind.data.frame(userindex, usersmiddle, useripaq)
dailyemafinal <- cbind.data.frame(dailyindex, dailytimes, dailytimes2, dailymiddle)
suggestfinal <- cbind.data.frame(suggesttimes, suggestavail, suggeststeps)
# jbsteps and gfsteps stay separate


# adding last and first ema response times to the user dataframe
# Note to later self: I really have no idea why this has to be so 
# complicated when it worked for steps.
userfinal$last.ema.response.utime <- as.POSIXct(
  with(dailyemafinal,
       tapply(ema.response.utime, user.index, max, na.rm=T)), 
  origin = "1970-01-01 00:00.00 UTC")

userfinal$first.ema.response.utime <- as.POSIXct(
  with(dailyemafinal,
       tapply(ema.response.utime, user.index, min, na.rm=T)), 
  origin = "1970-01-01 00:00.00 UTC")


write.csv(userfinal, "users.csv")
write.csv(dailyemafinal, "dailyema.csv")
write.csv(suggestfinal, "suggestions.csv")
write.csv(jbsteps, "jbsteps.csv")
write.csv(gfsteps, "gfsteps.csv")


