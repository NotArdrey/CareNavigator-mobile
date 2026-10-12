import {test,expect,withRole,goto,fill} from '../e2e_support.mjs';

const sections={
  patient:['','appointments','consultations','medical-records','labs','prescriptions','messages','notifications','profile'],
  doctor:['','scheduling','appointments','consultations','patients','results-review','prescriptions','laboratory','messages','notifications','profile'],
  hospital_admin:['','appointments','facility','availability','beds','rooms','emergency-room','services-departments','staff','audit-reports','notifications','profile'],
  super_admin:['','hospitals','approvals','accounts','system','analytics','notifications','profile'],
};
const roots={patient:'/patient',doctor:'/doctor',hospital_admin:'/hospital-admin',super_admin:'/super-admin'};
for(const [role,paths]of Object.entries(sections)){
  test(`${role}: fetch every workspace screen with real Supabase responses`,async()=>{
    test.setTimeout(240000);
    await withRole(role,async(page,context,evidence)=>{
      for(const section of paths){
        const path=roots[role]+(section?'/'+section:'');const start=evidence.requests.length;
        await goto(page,path);
        await expect(page.getByRole('button',{name:'Sign out',exact:true})).toBeVisible();
        await expect.poll(()=>evidence.requests.slice(start).filter(r=>r.method==='GET'&&r.status===200).length, {message:`${path} fetched persisted data`}).toBeGreaterThan(0);
        await expect(page.getByRole('button',{name:'Retry',exact:true})).toHaveCount(0);
        const tabs=page.getByRole('tab');const count=await tabs.count();
        for(let i=1;i<count;i++){
          const before=evidence.requests.length;await tabs.nth(i).click();
          await expect.poll(()=>evidence.requests.slice(before).filter(r=>r.status===200).length).toBeGreaterThan(0);
          await expect(page.getByRole('button',{name:'Retry',exact:true})).toHaveCount(0);
        }
      }
    });
  });
}
test('public discovery: real hospital/doctor fetch, filtering, detail and reload',async()=>withRole('guest',async(page,context,evidence)=>{
  await goto(page,'/hospitals');
  const details=page.getByRole('button',{name:'Details',exact:true});
  await expect(details.first()).toBeVisible();
  const initial=await details.count();expect(initial).toBeGreaterThan(0);
  const search=page.getByRole('textbox',{name:'Hospital, service, department, or location',exact:true});
  await fill(page,search,'no_such_hospital_e2e_12345');await expect(details).toHaveCount(0);
  await fill(page,search,'');await expect.poll(()=>details.count()).toBe(initial);
  await details.first().click();await expect(page).toHaveURL(/\/hospitals\//);
  const path=new URL(page.url()).pathname;await goto(page,path);
  await expect(page.getByRole('button',{name:'Retry',exact:true})).toHaveCount(0);
  await goto(page,'/doctors');
  await expect.poll(()=>evidence.requests.filter(r=>r.resource==='/rest/v1/doctors'&&r.status===200).length).toBeGreaterThan(0);
}));
