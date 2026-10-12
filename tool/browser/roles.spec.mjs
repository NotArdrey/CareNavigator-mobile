import {test,expect} from '@playwright/test';
import {launch,signIn,goto,baseUrl} from '../repair_browser_helpers.mjs';
const routes={super_admin:'/super-admin/system',hospital_admin:'/hospital-admin/appointments',doctor:'/doctor/scheduling',patient:'/patient/appointments',guest:'/hospitals'};
for(const [role,path]of Object.entries(routes)){
  test(`${role}: sign-in, protected deep link, reload and sign-out`,async()=>{
    const browser=await launch();
    try{
      const {page}=await signIn(browser,role);
      await goto(page,path);await expect(page).toHaveURL(baseUrl+path);
      await goto(page,path);await expect(page).toHaveURL(baseUrl+path);
      if(role!=='guest'){
        await page.getByRole('button',{name:'Sign out',exact:true}).click();
        await goto(page,path);await expect(page).toHaveURL(/\/sign-in\?from=/);
      }
    }finally{await browser.close();}
  });
}
test('expired recovery link offers a new-link action',async()=>{
  const browser=await launch();try{
    const context=await browser.newContext();const page=await context.newPage();
    await goto(page,'/reset-password?error_code=otp_expired');
    await expect(page.getByRole('button',{name:'Request a new recovery link',exact:true})).toBeVisible();
  }finally{await browser.close();}
});
