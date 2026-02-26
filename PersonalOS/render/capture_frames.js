const puppeteer = require("puppeteer");
(async()=>{
  const DURATION=process.env.DURATION?parseInt(process.env.DURATION):30;
  const FPS=process.env.FPS?parseInt(process.env.FPS):30;
  const TOTAL=DURATION*FPS;
  const VIEW={width:1280,height:720};
  const browser=await puppeteer.launch({headless:true,args:["--no-sandbox"]});
  const page=await browser.newPage();
  await page.setViewport(VIEW);
  await page.goto("file://"+process.cwd()+"/render/index.html",{waitUntil:"networkidle2"});
  for(let i=0;i<TOTAL;i++){
    await page.screenshot({path:`frame-${String(i+1).padStart(3,"0")}.png`});
    await page.waitForTimeout(1000/FPS);
  }
  await browser.close();
  console.log("Captured",TOTAL,"frames");
})();
