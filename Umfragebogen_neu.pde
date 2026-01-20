import java.io.*;
import java.util.*;

final String BASE_DIR  = "C:/Users/kiano/Uni/Bachelor/Bachelor-Arbeit/Processing_Projekte/UmfrageErgebnisse";
final String IMG_DIR   = "C:/Users/kiano/Uni/Bachelor/Bachelor-Arbeit/Processing_Projekte/Umfragebogen/bilder_sets";
final String GAZE_PATH = "C:/Users/kiano/Uni/Bachelor/Bachelor-Arbeit/Processing_Projekte/Umfragebogen/TobiiStream/gaze_output.txt";
String participantDir = "";

final String SEP = ";";
final int WELCOME=0, CONSENT=1, DEMO=2, TASKINFO=7, CALIB=8, TASK=3, POST_TRIAL=4, FINAL_SURVEY=5, THANKS=6, LOADING=9;
int state = LOADING;

boolean imagesLoaded = false;
boolean loadingStarted = false;

String[] geschlechtOpts = {"männlich", "weiblich", "divers"};
int geschlechtIndex = -1;
String ageStr = "";
boolean ageFocused = false;
String[] sehOpts = {"keine Sehhilfe", "Brille", "Kontaktlinsen"};
int sehIndex = -1;


String participantNoStr = "";
int participantNo = -1;

int radioYStep = 40;

boolean prevMousePressed = false;
boolean justClicked = false;

boolean clickPending = false;
int clickX = 0, clickY = 0;
int lastClickX = 0, lastClickY = 0;

boolean consentTextFocused = false;
int consentBoxX=40, consentBoxY=160, consentBoxW=240, consentBoxH=36;

final String[] ANIMALS = { "Katze", "Hund", "Pferd", "Hase" };

class Slot { int x,y,w,h; }
ArrayList<Slot> slots = new ArrayList<Slot>();

class IdImage {
  String id;
  PImage img;
  PImage full;
  IdImage(String id){ this.id=id; }
}

void saveLastSelectedImage(IdImage ii, int cond){
  lastSelectedDisplay = null;
  lastSelectedId = "";
  lastSelectedCond = cond;
  if (ii == null) return;
  lastSelectedId = ii.id;
  PImage src = (ii.full != null) ? ii.full : ii.img;
  if (src != null){
    lastSelectedDisplay = src.copy();
  }
}

HashMap<String, ArrayList<IdImage>> animalImgMap = new HashMap<String, ArrayList<IdImage>>();
HashMap<Integer, ArrayList<IdImage>> imgMap = new HashMap<Integer, ArrayList<IdImage>>();
HashMap<Integer, Integer> setIndex = new HashMap<Integer, Integer>();

boolean zoomOpen=false;
IdImage zoomImg=null;
String zoomId="";
int zoomCond=-1;
int zoomIdx=-1;

int rating = -1;

PImage lastSelectedDisplay = null;
String lastSelectedId = "";
int lastSelectedCond = -1;

PrintWriter trCsv;

float gazeX = Float.NaN, gazeY = Float.NaN;
long gaze_t_ms = -1;
RandomAccessFile gazeFile = null;
long gazeFilePos = 0;

SessionLogger sessionLogger;

class Experiment{
  String participantId="";
  int[] order = new int[4];
  int[] animalOrder = new int[4];
  int orderPos=0;
  int trialIndex=0;
  int genderIdx = -1;
  String age = "";
  int participantNo = -1;

  void startWithNo(int genderIdx, int pNo){
    this.genderIdx = genderIdx;
    this.participantNo = pNo;
    this.age = ageStr;
    participantId = timeStamp();
    int[][] latin = {
      {1,4,20,100},
      {4,20,100,1},
      {20,100,1,4},
      {100,1,4,20}
    };
    int idx = pNo % 4;
    order = latin[idx];
    int block = pNo / 4;
    for (int pos = 0; pos < animalOrder.length; pos++){
      animalOrder[pos] = (pos + block) % ANIMALS.length;
    }
    orderPos = 0;
    trialIndex = 0;
    String[] animalNamesForOrder = new String[animalOrder.length];
    for (int i = 0; i < animalOrder.length; i++){
      animalNamesForOrder[i] = ANIMALS[animalOrder[i]];
    }
    logEvent(
      DEMO,
      "EVENT_PARTICIPANT",
      "id="+participantId+
      ",participant_no="+pNo+
      ",gender_idx="+genderIdx+
      ",orderIndex="+idx+
      ",order="+join(intArrToStr(order),",")+
      ",animalOrderIdx="+join(intArrToStr(animalOrder),",")+
      ",animalOrderNames="+join(animalNamesForOrder,",")+
      ",age="+ageStr
    );
  }

  int currentCond(){
    return order[orderPos];
  }

  int currentAnimalIdx(){
    return animalOrder[orderPos];
  }

  String currentAnimal(){
    return ANIMALS[currentAnimalIdx()];
  }

  int animalIdxForCond(int cond){
    for (int pos = 0; pos < order.length; pos++){
      if (order[pos] == cond){
        return animalOrder[pos];
      }
    }
    return animalOrder[0];
  }

  String animalForCond(int cond){
    return ANIMALS[animalIdxForCond(cond)];
  }

  boolean nextCond(){
    orderPos++;
    trialIndex++;
    return orderPos < order.length;
  }
}
Experiment exp = new Experiment();

class CalibPoint {
  float nx, ny;
  boolean done = false;
  long insideSince = 0;
  CalibPoint(float nx, float ny){ this.nx=nx; this.ny=ny; }
}
ArrayList<CalibPoint> calibPoints = new ArrayList<CalibPoint>();
int calibHoldMs = 800;
float calibRadius = 0.11;

void settings(){ fullScreen(); }

void setup(){
  surface.setTitle("Umfrage + Eyetracking – vollständig");
  textFont(createFont("Arial", 20));
  background(22);
  buildSlots(2,2);
  buildCalibPoints();
  try{
    gazeFile = new RandomAccessFile(GAZE_PATH, "r");
    gazeFilePos = gazeFile.length();
  }catch(Exception e){}
  state = LOADING;
}

void draw(){
  if (clickPending) {
    justClicked = true;
    lastClickX = clickX;
    lastClickY = clickY;
  } else {
    justClicked = false;
  }
  clickPending = false;
  background(22);
  switch(state){
  case WELCOME:      drawWelcome();      break;
  case CONSENT:      drawConsent();      break;
  case DEMO:         drawDemographics(); break;
  case TASKINFO:     drawTaskInfo();     break;
  case CALIB:        drawCalibration();  break;
  case TASK:         drawTask();         break;
  case POST_TRIAL:   drawPostTrial();    break;
  case FINAL_SURVEY: drawFinalSurvey();  break;
  case THANKS:       drawThanks();       break;
  case LOADING:      drawLoading();      break;
  }
  pollGaze();
  prevMousePressed = mousePressed;
}

void drawWelcome(){
  title("Willkommen");
  body("Danke fürs Mitmachen! Klicke auf Weiter.");
  if (buttonCentered("Weiter", 160)) {
    state = CONSENT;
  }
}

boolean consentChecked=false;

void drawConsent(){
  title("Einverständnis & Teilnehmernummer");
  bodyLeft("Bitte Teilnehmer-Nr. eingeben (ganze Zahl ≥ 0) und zustimmen.", 40, 120);
  noFill(); stroke(consentTextFocused ? color(120,200,255) : color(180));
  rect(consentBoxX, consentBoxY, consentBoxW, consentBoxH, 8);
  noStroke(); fill(230); textAlign(LEFT,TOP);
  text(participantNoStr, consentBoxX+8, consentBoxY+8);
  if (consentTextFocused && ((millis()/500)%2==0)){
    int tw = int(textWidth(participantNoStr));
    stroke(230);
    line(consentBoxX+8+tw, consentBoxY+8, consentBoxX+8+tw, consentBoxY+consentBoxH-8);
    noStroke();
  }
  if (justClicked){
    if (over(consentBoxX, consentBoxY, consentBoxW, consentBoxH)) consentTextFocused = true;
    else consentTextFocused = false;
  }
  consentChecked = checkbox("Ich wurde über die Studie ausreichend informiert und habe mein Einverständnis schriftlich bestätigt.", 40, 220, consentChecked);
  boolean ok = consentChecked && participantNoStr.matches("\\d+");
  buttonDisabled(!ok);
  if (buttonCentered("Weiter", 160) && ok){
    participantNo = Integer.parseInt(participantNoStr);
    participantDir = BASE_DIR + "/Teilnehmer" + participantNo;
    File outDir = new File(participantDir);
    if (!outDir.exists()) outDir.mkdirs();
    sessionLogger = new SessionLogger(
      participantDir,
      geschlechtIndex,
      ageStr,
      participantNo
    );
    trCsv = createWriter(participantDir + "/trials.csv");
    trCsv.println("participant_id;participant_no;gender_idx;age;trial_index;condition;set_index;image_ids_shown;selected_image_id;zoom_count;regen_count;start_ms;select_ms;rt_ms");
    logEvent(CONSENT, "BTN_NEXT", "from=consent");
    state = DEMO;
  }
  buttonDisabled(false);
}

void drawDemographics(){
  title("Demografie");

  bodyLeft("Geschlecht:", 40, 140);
  geschlechtIndex = radioColumn(geschlechtOpts, 40, 170, radioYStep, geschlechtIndex);

  int yAfterGender = 170 + geschlechtOpts.length*radioYStep + 40;

  bodyLeft("Alter (in Jahren):", 40, yAfterGender);
  int ageBoxW = 160, ageBoxH = 36;
  noFill(); stroke(ageFocused ? color(120,200,255) : color(180));
  rect(40, yAfterGender+30, ageBoxW, ageBoxH, 8);

  noStroke(); fill(230); textAlign(LEFT,TOP);
  text(ageStr, 48, yAfterGender+36);

  if (justClicked){
    if (over(40, yAfterGender+30, ageBoxW, ageBoxH)) ageFocused = true;
    else ageFocused = false;
  }

  int yAfterAge = yAfterGender + 100;

  bodyLeft("Tragen Sie während dieser Studie eine Sehhilfe?", 40, yAfterAge);
  sehIndex = radioColumn(sehOpts, 40, yAfterAge + 40, radioYStep, sehIndex);

  boolean ok = (geschlechtIndex>=0 && ageStr.trim().length()>0 && sehIndex>=0);
  buttonDisabled(!ok);

  if (buttonCentered("Weiter", 160) && ok){
    logEvent(DEMO, "BTN_NEXT", 
      "gender_idx="+geschlechtIndex+
      ",age="+ageStr+
      ",seh="+sehOpts[sehIndex]
    );
    exp.startWithNo(geschlechtIndex, participantNo);
    prepareConditionImages();
    state = TASKINFO;
  }

  buttonDisabled(false);
}

void drawLoading(){
  title("Studie wird geladen...");
  body("Bitte warten, die Bilder werden vorbereitet.");
  if (!loadingStarted){
    loadingStarted = true;
    return;
  }
  if (!imagesLoaded){
    loadAllImages();
    imagesLoaded = true;
    return;
  }
  state = WELCOME;
}

void drawTaskInfo(){
  title("Aufgabenstellung");
  bodyLeft(
  "Aufgabe:\n" +
"• Sie haben die Aufgabe, für den Newsletter des Tierfreundeverbandes vier Titelbilder auszuwählen.\n" +
"• Dafür sehen Sie gleich Tierbilder von vier verschiedenen Tieren in vier verschiedenen Modi (1, 4, 20, 100).\n" +
"• Bitte wählen Sie für jedes Tier ein Bild aus, das Sie als Titelbild zufiedenstellend finden.\n" +
"• Sie sind nicht verpflichtet alle 100 Bilder anzuschauen.\n" +
"• Falls sie keines als passend empfinden, wählen Sie das zufriedenstellenste aus.\n" +
"• Mit den Pfeilen *Weiter* und *Zurück* können Sie zwischen den Sets navigieren.\n" +
"• Durch einen Klick auf ein Bild öffnet sich die Zoom-Ansicht." +
"• Mit *Schließen* können Sie diese Ansicht verlassen." +
"• *Auswählen* wählt das Bild, ohne spätere Änderung, aus.",
    40, 130
  );
  if (buttonCentered("Kalibrierung starten", 120)){
    logEvent(TASKINFO, "BTN_START_CALIB", "");
    resetCalibPoints();
    state = CALIB;
  }
}

void drawCalibration(){
  title("Eye-Tracking Kalibrier-Test");
  bodyLeft("Bitte schaue die Punkte nacheinander 1–2 Sekunden lang an.", 40, 90);

  boolean allDone = true;
  for (CalibPoint cp : calibPoints){
    if (!cp.done) {
      allDone = false;
      if (!Float.isNaN(gazeX) && !Float.isNaN(gazeY)){
        float dx = gazeX - cp.nx;
        float dy = gazeY - cp.ny;
        float dist = sqrt(dx*dx + dy*dy);
        if (dist < calibRadius){
          if (cp.insideSince == 0) cp.insideSince = millis();
          else if (millis() - cp.insideSince >= calibHoldMs){
            cp.done = true;
            logEvent(CALIB, "CALIB_POINT_DONE", "nx="+cp.nx+",ny="+cp.ny);
          }
        } else {
          cp.insideSince = 0;
        }
      }
    }
  }

  for (CalibPoint cp : calibPoints){
    if (!cp.done){
      int cx = int(cp.nx * width);
      int cy = int(cp.ny * height);
      noStroke();
      fill(200, 60, 60);
      ellipse(cx, cy, 28, 28);
    }
  }

  if (allDone && buttonCentered("Weiter", 120)){
    logEvent(CALIB, "BTN_NEXT", "from=calibration");
    beginCondition(exp.currentCond());
    state = TASK;
  }
}


void buildCalibPoints(){
  calibPoints.clear();
  calibPoints.add(new CalibPoint(0.08, 0.08));
  calibPoints.add(new CalibPoint(0.5, 0.08));
  calibPoints.add(new CalibPoint(0.92, 0.08));
  calibPoints.add(new CalibPoint(0.08, 0.5));
  calibPoints.add(new CalibPoint(0.92, 0.5));
  calibPoints.add(new CalibPoint(0.08, 0.92));
  calibPoints.add(new CalibPoint(0.5, 0.92));
  calibPoints.add(new CalibPoint(0.92, 0.92));
}
void resetCalibPoints(){
  for (CalibPoint cp : calibPoints){
    cp.done = false;
    cp.insideSince = 0;
  }
}

int regenCountThisTrial=0, zoomCountThisTrial=0;
long trialStartMs=0;
boolean firstShowThisSet=true;

void drawTask(){
  int cond = exp.currentCond();
  title("Bedingung: "+cond+" Bild(e)");
if (firstShowThisSet){
  trialStartMs = millis();
  regenCountThisTrial = 0;
  zoomCountThisTrial = 0;
  firstShowThisSet = false;

  if (sessionLogger != null){
    sessionLogger.startSetOrSegment(cond, setIndex.get(cond));
  }
}
  if (cond==1){
    renderSingle();
  } else if (cond==4){
    buildSlots(2,2); renderGrid(cond);
  } else if (cond==20){
    buildSlots(5,4); renderGrid(cond);
  } else if (cond==100){
    buildSlots(10,10); renderGrid(cond);
  }
  if (zoomOpen && cond != 1) return;
  int y = height-90;
  if (cond!=100){
    boolean leftEnabled  = canLeft(cond);
    boolean rightEnabled = canRight(cond);
    if (leftEnabled){
      if (button(40, y, 140, 44, "← Zurück")){
        prevSet(cond);
        logEvent(TASK,"NAV_BACK", currentSetPayload(cond));
      }
    }
    buttonDisabled(!rightEnabled);
    int rightX = width - 240;
    if (button(rightX, y, 180, 44, "→ Weiter") && rightEnabled){
      nextSet(cond);
      regenCountThisTrial++;
      logEvent(TASK,"NAV_FWD", currentSetPayload(cond));
    }
    buttonDisabled(false);
  }
}

void renderSingle(){
  ArrayList<IdImage> set = currentSet(exp.currentCond());
  imageMode(CENTER);
  if (set==null || set.size()==0){
    noFill(); stroke(120); rect(int(width*0.2), int(height*0.2), int(width*0.6), int(height*0.6), 10);
    fill(200); noStroke(); textAlign(CENTER,CENTER);
    text("Kein Bild im aktuellen Set", width/2, height/2);
    return;
  }
  IdImage ii = set.get(0);
  if (ii.img != null){
    image(ii.img, width/2, height/2-20, width*0.6, height*0.6);
  } else {
    noFill(); stroke(120); rect(int(width*0.2), int(height*0.2), int(width*0.6), int(height*0.6), 10);
    fill(200); noStroke(); textAlign(CENTER,CENTER);
    text("Lade Bild...", width/2, height/2);
  }
  int selW = 200, selH = 56;
  int selX = width/2 - selW/2;
  int selY = height-90;
  if (button(selX, selY, selW, selH, "Auswählen")){
  long selMs = millis();
  int cond = exp.currentCond();
  int sIdx = setIndex.get(cond);

  saveLastSelectedImage(ii, cond);
  writeTrial(ii.id, selMs);

  logEvent(TASK, "EVENT_SELECT",
    "image_id="+ii.id+
    ",cond="+cond+
    ",set="+sIdx+
    ",animal_idx="+exp.currentAnimalIdx()+
    ",animal_name="+exp.currentAnimal()
  );

  if (sessionLogger != null){
    sessionLogger.closeCurrentZoom();
    sessionLogger.closeCurrentView();
  }

  rating = -1;
  state = POST_TRIAL;
}
}

void renderGrid(int cond){
  ArrayList<IdImage> set = currentSet(cond);
  if (set==null) return;
  imageMode(CENTER);
  for (int i=0; i<set.size() && i<slots.size(); i++){
    Slot s = slots.get(i);
    IdImage ii = set.get(i);
    noFill(); stroke(80); rect(s.x, s.y, s.w, s.h, 10);
    if (ii.img != null){
      float scale = min((float)s.w / ii.img.width, (float)s.h / ii.img.height);
      int dw = int(ii.img.width * scale), dh = int(ii.img.height * scale);
      int dx = s.x + s.w/2, dy = s.y + s.h/2;
      image(ii.img, dx, dy, dw, dh);
    } else {
      fill(200); noStroke(); textAlign(CENTER,CENTER);
      text("lade...", s.x + s.w/2, s.y + s.h/2);
    }
    if (justClicked && !zoomOpen && over(s.x, s.y, s.w, s.h)){
      zoomOpen=true; zoomImg=ii; zoomId=ii.id; zoomCond=cond; zoomIdx=i; zoomCountThisTrial++;
      logEvent(TASK, "EVENT_ZOOM_OPEN", "cond="+cond+",image_idx="+i+",image_id="+ii.id);
    }
  }
  drawZoomIfOpen();
}

void drawZoomIfOpen(){
  if (!zoomOpen) return;

  // Full nachladen (nur falls noch nicht da)
  if (zoomImg != null && zoomImg.full == null && zoomCond != -1){
    String pathFull = IMG_DIR + "/" + folderForCond(zoomCond) + "/" + zoomImg.id;
    PImage fullLoaded = safeLoad(pathFull);
    if (fullLoaded != null){
      zoomImg.full = fullLoaded;
    }
  }

  fill(0,180); 
  noStroke(); 
  rect(0,0,width,height);

  PImage imgToShow =
    (zoomImg != null && zoomImg.full != null) ? zoomImg.full :
    (zoomImg != null ? zoomImg.img : null);

  float mw = width*0.8;
  float mh = height*0.8;
  if (imgToShow != null){
    imageMode(CENTER);
    image(imgToShow, width/2, height/2, mw, mh);
  }

  fill(240);
  textAlign(LEFT,TOP);
  text("ID: "+zoomId, 40, 40);

  if (button(width/2-100, height-90, 200, 56, "Auswählen")){
    long selMs = millis();

    int cond = (zoomCond != -1) ? zoomCond : exp.currentCond();
    int sIdx = setIndex.get(cond);

    saveLastSelectedImage(zoomImg, cond);
    writeTrial(zoomId, selMs);

    logEvent(
      TASK,
      "EVENT_SELECT",
      "image_id="+zoomId+
      ",cond="+cond+
      ",set="+sIdx+
      ",animal_idx="+exp.currentAnimalIdx()+
      ",animal_name="+exp.currentAnimal()
    );

    if (sessionLogger != null){
      sessionLogger.closeCurrentZoom();
      sessionLogger.closeCurrentView();
    }

    zoomOpen=false; 
    zoomImg=null; 
    zoomId=""; 
    zoomCond=-1; 
    zoomIdx=-1;

    rating = -1;
    state = POST_TRIAL;
    return;
  }

  if (button(40, 40, 160, 44, "Schließen")){
    logEvent(
      TASK,
      "EVENT_ZOOM_CLOSE",
      "image_id="+zoomId+
      ",cond="+((zoomCond != -1) ? zoomCond : exp.currentCond())
    );

    zoomOpen=false; 
    zoomImg=null; 
    zoomId=""; 
    zoomCond=-1; 
    zoomIdx=-1;
  }
}

void writeTrial(String selectedId, long selMs){
  if (trCsv == null) return;
  int cond = exp.currentCond();
  int sIdx = setIndex.get(cond);
  String[] shown = currentSetIds(cond);
  long rt = selMs - trialStartMs;
  trCsv.println(
    exp.participantId + SEP +
    participantNo + SEP +
    geschlechtIndex + SEP +
    ageStr + SEP +
    exp.trialIndex + SEP +
    cond + SEP +
    sIdx + SEP +
    join(shown,",") + SEP +
    selectedId + SEP +
    zoomCountThisTrial + SEP +
    regenCountThisTrial + SEP +
    trialStartMs + SEP +
    selMs + SEP +
    rt
  );
  trCsv.flush();
}

void drawPostTrial(){
  title("Kurze Bewertung");
  int imgAreaTop = 100;
  int imgAreaH   = int(height * 0.4);
  if (lastSelectedDisplay != null){
    imageMode(CENTER);
    float maxW = width * 0.6;
    float maxH = imgAreaH;
    float scale = min(maxW / lastSelectedDisplay.width,
                      maxH / lastSelectedDisplay.height);
    int dw = int(lastSelectedDisplay.width  * scale);
    int dh = int(lastSelectedDisplay.height * scale);
    image(lastSelectedDisplay, width/2, imgAreaTop + imgAreaH/2, dw, dh);
  }
  int qY = imgAreaTop + imgAreaH + 40;
  bodyLeft("Wie zufrieden sind Sie mit Ihrer Auswahl? (1 = gar nicht, 7 = sehr)", 40, qY);
  rating = likert7(40, qY + 50, rating);
  boolean ok = (rating >= 1);
  buttonDisabled(!ok);
  if (buttonCentered("Weiter", 80) && ok){
    logEvent(
      POST_TRIAL,
      "EVENT_POST_TRIAL",
      "q_satisfaction_1_7="+rating+
      ",selected_id="+lastSelectedId+
      ",cond="+lastSelectedCond+
      ",animal_idx="+exp.currentAnimalIdx()+
      ",animal_name="+exp.currentAnimal()
    );
    if (exp.nextCond()){
      beginCondition(exp.currentCond());
      state = TASK;
    } else {
      state = FINAL_SURVEY;
    }
  }
  buttonDisabled(false);
}

int favIdx=-1;

void drawFinalSurvey(){
  title("Abschluss");

  bodyLeft("Mit welchem Modus würden Sie am liebsten weiterarbeiten?", 40, 140);
  String[] favs = {"1 Bild","4 Bilder","20 Bilder","100 Bilder"};
  favIdx = radioRow(favs, 40, 170, favIdx);

  boolean ok = (favIdx>=0);
  buttonDisabled(!ok);

  if (buttonCentered("Abschließen", 160) && ok){
    int favCond = new int[]{1,4,20,100}[favIdx];
    logEvent(FINAL_SURVEY, "EVENT_FINAL_FAVORITE", "fav="+favCond);
    state = THANKS;
  }

  buttonDisabled(false);
}

void drawThanks(){
  title("Vielen Dank!");
  body("Deine Teilnahme ist beendet.");
  if (buttonCentered("Beenden", 160)) {
    logEvent(THANKS, "BTN_EXIT", "from=thanks");
    safeExit();
  }
}

void loadAllImages(){
  animalImgMap.clear();
  for (String animal : ANIMALS){
    ArrayList<IdImage> list = new ArrayList<IdImage>();
    String folder = animal.toLowerCase();
    File dir = new File(IMG_DIR + "/" + folder);
    File[] files = dir.listFiles();
    if (files != null){
      Arrays.sort(files);
      for (int i=0; i<files.length && i<100; i++){
        if (!files[i].isFile()) continue;
        String name = files[i].getName().toLowerCase();
        if (!name.matches(".*\\.(png|jpg|jpeg)$")) continue;
        IdImage ii = new IdImage(files[i].getName());
        String path = IMG_DIR + "/" + folder + "/" + ii.id;
        PImage img = safeLoad(path);
        if (img != null){
          int maxW = width/2;
          int maxH = height/2;
          if (img.width > maxW || img.height > maxH){
            img.resize(maxW, 0);
            if (img.height > maxH) img.resize(0, maxH);
          }
          ii.img = img;
        }
        list.add(ii);
      }
    }
    animalImgMap.put(animal, list);
  }
}

void prepareConditionImages(){
  imgMap.clear();
  setIndex.clear();
  int[] conds = {1,4,20,100};
  for (int c : conds){
    String animal = exp.animalForCond(c);
    ArrayList<IdImage> base = animalImgMap.get(animal);
    if (base == null) base = new ArrayList<IdImage>();
    imgMap.put(c, base);
    setIndex.put(c, 0);
  }
}

void beginCondition(int cond){
  firstShowThisSet = true;
  int mx = maxSetsFor(cond);
  int idx = setIndex.get(cond);
  if (idx>=mx) setIndex.put(cond, max(0, mx-1));
}

int maxSetsFor(int cond){
  ArrayList<IdImage> base = imgMap.get(cond);
  int cap = (cond==1?100: cond==4?25: cond==20?5: cond==100?1:0);
  int have = (base==null)?0 : base.size()/max(1,cond);
  return min(cap, have);
}

boolean canLeft(int cond){
  Integer idx = setIndex.get(cond);
  return idx!=null && idx>0;
}
boolean canRight(int cond){
  Integer idx = setIndex.get(cond);
  return idx!=null && idx < maxSetsFor(cond)-1;
}

void nextSet(int cond){
  int idx = setIndex.get(cond);
  int mx = maxSetsFor(cond);
  if (idx < mx-1){
    setIndex.put(cond, idx+1);
    firstShowThisSet = true;
  }
}

void prevSet(int cond){
  int idx = setIndex.get(cond);
  if (idx>0){
    setIndex.put(cond, idx-1);
    firstShowThisSet=true;
  }
}

ArrayList<IdImage> currentSet(int cond){
  ArrayList<IdImage> base = imgMap.get(cond);
  if (base==null) return null;
  int size = cond;
  int sIdx = setIndex.get(cond);
  int start = sIdx * size;
  ArrayList<IdImage> out = new ArrayList<IdImage>();
  for (int i=0; i<size && start+i<base.size(); i++) out.add(base.get(start+i));
  return out;
}

String[] currentSetIds(int cond){
  ArrayList<IdImage> set = currentSet(cond);
  if (set==null) return new String[0];
  String[] ids = new String[set.size()];
  for (int i=0;i<set.size();i++) ids[i]=set.get(i).id;
  return ids;
}

String currentSetPayload(int cond){
  return "cond="+cond+
         ",set="+setIndex.get(cond)+
         ",animal_idx="+exp.currentAnimalIdx()+
         ",animal_name="+exp.currentAnimal()+
         ",ids="+join(currentSetIds(cond),"|");
}

double tobiiT0 = Double.NaN;

void pollGaze(){
  try{
    if (gazeFile == null) return;

    long len = gazeFile.length();
    if (len < gazeFilePos) gazeFilePos = 0;
    if (len <= gazeFilePos) return;

    gazeFile.seek(gazeFilePos);
    String line;

    while ((line = gazeFile.readLine()) != null){
      String t = trim(line);
      if (!t.startsWith("TobiiStream")) continue;

      String[] parts = splitTokens(t, " ");
      if (parts.length < 4) continue;

      double ts = Double.parseDouble(parts[1]);   // <-- Timestamp aus Datei
      float  x  = parseFloat(parts[2]);
      float  y  = parseFloat(parts[3]);

      if (Double.isNaN(tobiiT0)) tobiiT0 = ts;
      long gms = (long)((ts - tobiiT0) * 1.0);     // ts ist hier schon in ms-Einheiten

      float gx = constrain(x / 1920.0, 0, 1);
      float gy = constrain(y / 1080.0, 0, 1);

      gazeX = gx; gazeY = gy;
      if (sessionLogger != null) sessionLogger.logGaze(gms, gx, gy);
    }

    gazeFilePos = gazeFile.getFilePointer();
  }catch(Exception e){}
}

int extractInt(String payload, String key){
  if (payload == null) return -1;
  String[] parts = splitTokens(payload, ",;");
  for (String p : parts){
    p = trim(p);
    if (p.startsWith(key + "=")){
      String v = p.substring((key + "=").length());
      try {
        return Integer.parseInt(v);
      } catch(Exception e){
        return -1;
      }
    }
  }
  return -1;
}

void logEvent(int st, String e, String payload){
  if (sessionLogger == null) return;

  float gx = gazeX;
  float gy = gazeY;

  if (e.equals("EVENT_SHOW_SET")){
    int cond = extractInt(payload, "cond");
    int set  = extractInt(payload, "set");
    if (cond != -1 && set != -1){
      sessionLogger.startSetOrSegment(cond, set);
    }
    sessionLogger.log(st, e, payload, gx, gy);
    return;
  }

  if (e.equals("NAV_FWD") || e.equals("NAV_BACK")){
    sessionLogger.log(st, e, payload, gx, gy);
    return;
  }

  if (e.equals("EVENT_ZOOM_OPEN")){
    int cond = extractInt(payload, "cond");
    int idx  = extractInt(payload, "image_idx");
    if (cond != -1){
      if (idx == -1) idx = 0;
      sessionLogger.startZoom(cond, idx);
    }
    sessionLogger.log(st, e, payload, gx, gy);
    return;
  }

  if (e.equals("EVENT_ZOOM_CLOSE")){
    sessionLogger.log(st, e, payload, gx, gy);
    sessionLogger.closeCurrentZoom();
    sessionLogger.startNewViewSegment();
    return;
  }

  sessionLogger.log(st, e, payload, gx, gy);
}

void title(String s){
  fill(240);
  textAlign(CENTER,TOP);
  textSize(28);
  text(s, width/2, 30);
  textAlign(LEFT,BASELINE);
  textSize(20);
}
void body(String s){
  fill(210);
  textAlign(CENTER,TOP);
  text(s, width/2, 80);
  textAlign(LEFT,BASELINE);
}
void bodyLeft(String s, int x, int y){
  fill(210);
  textAlign(LEFT,TOP);
  text(s, x, y);
  textAlign(LEFT,BASELINE);
}

boolean button(int x, int y, int w, int h, String label){
  noStroke(); fill(60,160,90); rect(x, y, w, h, 8);
  fill(255); textAlign(CENTER,CENTER);
  text(label, x+w/2, y+h/2);
  textAlign(LEFT,BASELINE);
  return !btnDisabled && clickInside(x, y, w, h);
}
boolean btnDisabled=false;
void buttonDisabled(boolean d){ btnDisabled=d; }
boolean buttonCentered(String label, int yOff){
  int w=220,h=48;
  int x=width/2-w/2;
  int y=height - yOff;
  noStroke();
  fill(btnDisabled?90:60, btnDisabled?90:160, btnDisabled?90:90);
  rect(x,y,w,h,8);
  fill(255); textAlign(CENTER,CENTER);
  text(label, x+w/2, y+h/2);
  textAlign(LEFT,BASELINE);
  return !btnDisabled && clickInside(x, y, w, h);
}

boolean checkbox(String label, int x, int y, boolean val){
  int s=24;
  noFill(); stroke(200); rect(x,y,s,s,4);
  if (val){ line(x,y,x+s,y+s); line(x+s,y,x,y+s); }
  noStroke(); fill(220); textAlign(LEFT,TOP); text(label, x+s+10, y+2); textAlign(LEFT,BASELINE);
  if (clickInside(x,y,s,s)) val=!val;
  return val;
}
int radioColumn(String[] opts, int x, int y, int step, int sel){
  for (int i=0;i<opts.length;i++){
    int r=10;
    int cx=x+r, cy=y+i*step+r;
    noFill();
    stroke(sel==i? color(80,200,255): color(180));
    strokeWeight(2);
    ellipse(cx,cy,2*r,2*r);
    if (sel==i){
      noStroke();
      fill(80,200,255);
      ellipse(cx,cy,r,r);
    }
    fill(230);
    text(opts[i], x+2*r+10, cy+6);
    if (justClicked && dist(lastClickX,lastClickY,cx,cy)<=r) sel=i;
  }
  return sel;
}

int radioRow(String[] opts, int x, int y, int sel){
  int bx=x;
  for (int i=0;i<opts.length;i++){
    int w=max(160, int(textWidth(opts[i])+36));
    noStroke();
    fill(sel==i?120:60);
    rect(bx, y, w, 36, 8);
    fill(240);
    textAlign(CENTER,CENTER);
    text(opts[i], bx+w/2, y+18);
    textAlign(LEFT,BASELINE);
    if (justClicked && over(bx,y,w,36)) sel=i;
    bx+=w+12;
  }
  return sel;
}

int likert7(int x, int y, int sel){
  int r = 16;
  int step = 56;
  textSize(18);
  for (int i = 1; i <= 7; i++){
    int cx = x + (i-1)*step;
    int cy = y;
    noFill();
    stroke(sel == i ? color(80,200,255) : color(180));
    strokeWeight(2);
    ellipse(cx, cy, 2*r, 2*r);
    if (sel == i){
      noStroke();
      fill(80,200,255);
      ellipse(cx, cy, r, r);
    }
    fill(230);
    textAlign(CENTER, TOP);
    text(i, cx, y + r + 10);
    textAlign(LEFT, BASELINE);
    if (justClicked && dist(mouseX, mouseY, cx, cy) <= r) sel = i;
  }
  textSize(20);
  return sel;
}

boolean over(int x,int y,int w,int h){
  return lastClickX>=x && lastClickX<=x+w && lastClickY>=y && lastClickY<=y+h;
}
boolean clickInside(int x, int y, int w, int h){
  return justClicked && over(x,y,w,h);
}

void buildSlots(int cols, int rows){
  slots.clear();

  if (cols == 10 && rows == 10){
    int top = 90;
    int bottomMargin = 50;

    int maxGridH = height - top - bottomMargin;

    float widthFactor = 0.85f;
    int targetGridW = int(width * widthFactor);

    float targetAspect = 16.0f / 9.0f;

    int cellW = targetGridW / cols;
    int cellH = int(cellW / targetAspect);

    int gridH = cellH * rows;


    if (gridH > maxGridH){
      float scale = (float)maxGridH / (float)gridH;
      cellW = int(cellW * scale);
      cellH = int(cellH * scale);
      gridH = cellH * rows;
    }

    int gridW = cellW * cols;

    int startX = (width - gridW) / 2;

    int innerPad = 4;

    for (int r = 0; r < rows; r++){
      for (int c = 0; c < cols; c++){
        Slot s = new Slot();
        s.x = startX + c * cellW + innerPad/2;
        s.y = top    + r * cellH + innerPad/2;
        s.w = cellW - innerPad;
        s.h = cellH - innerPad;
        slots.add(s);
      }
    }

  } else {
    int margin = 20;
    int top = 100;

    int gridW = width - margin*2;
    int gridH = height - top - margin - 120;

    int cellW = gridW / cols;
    int cellH = gridH / rows;

    for (int r = 0; r < rows; r++){
      for (int c = 0; c < cols; c++){
        Slot s = new Slot();
        s.x = margin + c * cellW + 10;
        s.y = top    + r * cellH + 10;
        s.w = cellW - 20;
        s.h = cellH - 20;
        slots.add(s);
      }
    }
  }
}




void keyTyped(){
  if (state==CONSENT && consentTextFocused){
    if (key>='0' && key<='9'){
      participantNoStr += key;
    } else if (key==BACKSPACE){
      if (participantNoStr.length()>0) participantNoStr = participantNoStr.substring(0, participantNoStr.length()-1);
    } else if (key==DELETE){
      participantNoStr = "";
    } else if (key==ENTER || key==RETURN){
      if (consentChecked && participantNoStr.matches("\\d+")){
        participantNo = Integer.parseInt(participantNoStr);
        participantDir = BASE_DIR + "/Teilnehmer" + participantNo;
        File outDir = new File(participantDir);
        if (!outDir.exists()) outDir.mkdirs();
        sessionLogger = new SessionLogger(
          participantDir,
          geschlechtIndex,
          ageStr,
          participantNo
        );
        trCsv = createWriter(participantDir + "/trials.csv");
        trCsv.println("participant_id;participant_no;gender_idx;age;trial_index;condition;set_index;image_ids_shown;selected_image_id;zoom_count;regen_count;start_ms;select_ms;rt_ms");
        logEvent(CONSENT, "BTN_NEXT", "from=consent_enter");
        state = DEMO;
      }
    }
  } else if (state==DEMO && ageFocused){
    if (key>='0' && key<='9'){
      ageStr += key;
    } else if (key==BACKSPACE){
      if (ageStr.length()>0) ageStr = ageStr.substring(0, ageStr.length()-1);
    } else if (key==DELETE){
      ageStr = "";
    }
  }
}

void mouseReleased() {
  clickPending = true;
  clickX = mouseX;
  clickY = mouseY;
}

String timeStamp(){ return nf(year(),4)+nf(month(),2)+nf(day(),2)+"_"+nf(hour(),2)+nf(minute(),2)+nf(second(),2); }
PImage safeLoad(String path){ if (path==null || path.trim().isEmpty()) return null; try{ return loadImage(path);}catch(Exception e){ return null;} }
String[] intArrToStr(int[] a){ String[] s=new String[a.length]; for(int i=0;i<a.length;i++) s[i]=str(a[i]); return s; }

String folderForCond(int cond){
  if (exp == null) return ANIMALS[0];
  return exp.animalForCond(cond).toLowerCase();
}

void safeExit(){
  try{ if (trCsv!=null){ trCsv.flush(); trCsv.close(); } }catch(Exception e){}
  try{ if (sessionLogger!=null){ sessionLogger.closeAll(); } }catch(Exception e){}
  exit();
}

void exit(){
  try{ if (trCsv!=null){ trCsv.flush(); trCsv.close(); } }catch(Exception e){}
  try{ if (sessionLogger!=null){ sessionLogger.closeAll(); } }catch(Exception e){}
  try{ if (gazeFile!=null){ gazeFile.close(); gazeFile=null; } }catch(Exception e){}
  super.exit();
}

class SessionLogger {
  String baseDir;
  int genderIdx;
  String ageStr;
  int participantNo;
  PrintWriter rawCsv;
  PrintWriter actionsCsv;
  PrintWriter currentViewCsv = null;
  PrintWriter currentZoomCsv = null;
  int currentCond = -1;
  int currentSetIdx = -1;
  int currentSetSegment = 0;
  int zoomCounter = 0;
  int logCounter = 0;

  SessionLogger(String dir, int genderIdx, String ageStr, int participantNo){
    this.baseDir = dir;
    this.genderIdx = genderIdx;
    this.ageStr = ageStr;
    this.participantNo = participantNo;
    rawCsv = createWriter(baseDir + "/raw.csv");
    rawCsv.println("ms;state;event;payload;gx;gy");
    String ts = timeStamp();
    actionsCsv = createWriter(baseDir + "/actions_" + ts + ".csv");
    actionsCsv.println("participant_no;" + participantNo);
    actionsCsv.println("gender_idx;" + genderIdx);
    actionsCsv.println("age;" + ageStr);
    actionsCsv.println("----");
    actionsCsv.println("ms;state;event;payload;gx;gy");
  }

  String condName(int cond){
    if (cond == 1)   return "1er";
    if (cond == 4)   return "4er";
    if (cond == 20)  return "20er";
    if (cond == 100) return "100er";
    return cond + "er";
  }

  void startSetOrSegment(int cond, int setIndex){
    if (cond == currentCond && setIndex == currentSetIdx){
      startNewViewSegment();
    } else {
      currentCond = cond;
      currentSetIdx = setIndex;
      currentSetSegment = 0;
      startNewViewSegment();
    }
  }

  void startNewViewSegment(){
    closeCurrentView();
    currentSetSegment++;
    int dispSet = currentSetIdx + 1;
    String name = condName(currentCond) + ".Set" + dispSet + "." + currentSetSegment + ".csv";
    currentViewCsv = createWriter(baseDir + "/" + name);
    currentViewCsv.println("ms;state;event;payload;gx;gy");
  }

  void closeCurrentView(){
    if (currentViewCsv != null){
      currentViewCsv.flush();
      currentViewCsv.close();
      currentViewCsv = null;
    }
  }

  void startZoom(int cond, int imageNo){
    closeCurrentZoom();
    zoomCounter++;
    int dispImg = imageNo + 1;
    String name = condName(cond) + ".Bild" + dispImg + "Zoom." + zoomCounter + ".csv";
    currentZoomCsv = createWriter(baseDir + "/" + name);
    currentZoomCsv.println("ms;state;event;payload;gx;gy");
  }

  void closeCurrentZoom(){
    if (currentZoomCsv != null){
      currentZoomCsv.flush();
      currentZoomCsv.close();
      currentZoomCsv = null;
    }
  }

void log(int st, String ev, String payload, float gx, float gy){
  int now = millis();

  if (rawCsv != null){
    rawCsv.println(now + ";" + st + ";" + ev + ";" + payload + ";" + gx + ";" + gy);
  }

  if (actionsCsv != null && !ev.equals("GAZE")){
    actionsCsv.println(now + ";" + st + ";" + ev + ";" + payload + ";" + gx + ";" + gy);
  }

  if (currentZoomCsv != null){
    currentZoomCsv.println(now + ";" + st + ";" + ev + ";" + payload + ";" + gx + ";" + gy);
  } else if (currentViewCsv != null){
    currentViewCsv.println(now + ";" + st + ";" + ev + ";" + payload + ";" + gx + ";" + gy);
  }

  logCounter++;
  if (logCounter % 50 == 0){
    try{
      if (rawCsv != null) rawCsv.flush();
      if (actionsCsv != null) actionsCsv.flush();
      if (currentViewCsv != null) currentViewCsv.flush();
      if (currentZoomCsv != null) currentZoomCsv.flush();
    }catch(Exception e){}
  }
}


int gazeCounter = 0;

void logGaze(long gms, float gx, float gy){
  if (rawCsv != null){
    rawCsv.println(gms + ";-1;GAZE;;" + gx + ";" + gy);
  }

  if (currentZoomCsv != null){
    currentZoomCsv.println(gms + ";-1;GAZE;;" + gx + ";" + gy);
  } else if (currentViewCsv != null){
    currentViewCsv.println(gms + ";-1;GAZE;;" + gx + ";" + gy);
  }

  gazeCounter++;
  if (gazeCounter % 50 == 0){
    try{
      if (rawCsv != null) rawCsv.flush();
      if (currentViewCsv != null) currentViewCsv.flush();
      if (currentZoomCsv != null) currentZoomCsv.flush();
    }catch(Exception e){}
  }
}

  void closeAll(){
    closeCurrentZoom();
    closeCurrentView();
    try{
      if (rawCsv != null){
        rawCsv.flush();
        rawCsv.close();
      }
    }catch(Exception e){}
    try{
      if (actionsCsv != null){
        actionsCsv.flush();
        actionsCsv.close();
      }
    }catch(Exception e){}
  }
}
