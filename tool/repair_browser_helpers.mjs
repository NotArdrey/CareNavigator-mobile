import {chromium} from 'playwright';
import {accounts} from './repair_fixture_api.mjs';
export const baseUrl='http://127.0.0.1:3000';
export async function launch(){return chromium.launch({headless:true,
  executablePath:process.env.CNPH_BROWSER_PATH??'C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe',
  args:['--use-fake-ui-for-media-stream','--use-fake-device-for-media-stream']});}
export async function enable(page){
  const placeholder=page.locator('flt-semantics-placeholder');
  await placeholder.waitFor({timeout:30000});
  await placeholder.evaluate(e=>e.click());
  await page.waitForTimeout(350);
}
export async function goto(page,path){
  await page.goto(baseUrl+path);await enable(page);await page.waitForTimeout(900);
}
export async function fill(page,locator,value){
  await locator.click();await page.waitForTimeout(150);
  await page.keyboard.press('Control+A');await page.keyboard.press('Backspace');
  if(value)await page.keyboard.type(value,{delay:5});
  await page.keyboard.press('Tab');await page.waitForTimeout(150);
}
export async function signIn(browser,role){
  const context=await browser.newContext({viewport:{width:1440,height:1100},timezoneId:'Asia/Manila',permissions:['camera','microphone']});
  const page=await context.newPage();
  await goto(page,'/sign-in');
  const account=accounts.accounts.find(a=>a.role===role);
  await page.getByRole('textbox',{name:'Email address',exact:true}).click();await page.waitForTimeout(200);
  await page.keyboard.type(account.email,{delay:5});await page.keyboard.press('Tab');await page.waitForTimeout(200);
  await page.keyboard.type(accounts.password,{delay:5});await page.keyboard.press('Tab');await page.waitForTimeout(200);
  await page.getByRole('button',{name:'Sign in',exact:true}).click();
  await page.waitForURL(u=>u.pathname!='/sign-in',{timeout:30000});
  return {context,page};
}
export async function controls(page){
  const cdp=await page.context().newCDPSession(page);
  const {nodes}=await cdp.send('Accessibility.getFullAXTree');await cdp.detach();
  return nodes.map(n=>({role:n.role?.value,name:n.name?.value})).filter(n=>['button','textbox','checkbox','switch','combobox','tab','heading'].includes(n.role));
}
