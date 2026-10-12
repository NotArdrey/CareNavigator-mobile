import {test,expect,withRole,goto,fill,rest,prefix,isolateHospital,restoreHospital,submit,choose} from '../e2e_support.mjs';
import {management} from '../repair_backend.mjs';
import {accounts,base,publicKey,api} from '../repair_fixture_api.mjs';
let isolation;
test.beforeAll(async()=>{isolation=await isolateHospital();});
test.afterAll(async()=>{if(isolation)await restoreHospital(isolation);});

test('doctor staff: browser provisioning, fetch, suspension/login denial, reactivation and cleanup',async()=>withRole('hospital_admin',async page=>{
  const email=`repair-e2e-doctor-${Date.now()}@example.test`;let authId;
  const [department]=await rest('hospital_admin','hospital_departments','',{
    hospital_id:isolation.hospitalId,department_name:prefix+' provisioned department',description:'Synthetic verification only'},'POST');
  const verifyBrowserStatus=async(userId,status)=>{
    const pending=page.waitForResponse(r=>{
      const url=new URL(r.url());
      return url.pathname==='/rest/v1/users'&&url.searchParams.get('id')===`eq.${userId}`&&r.request().method()==='GET';
    });
    await goto(page,'/hospital-admin/staff/'+userId);
    const response=await pending;const [row]=await response.json();
    expect(response.status()).toBe(200);expect(row.account_status).toBe(status);
    await expect(page.getByRole('heading',{name:'Record detail',exact:true})).toBeVisible();
    await page.screenshot({path:`.codex-runtime/e2e/staff-${status}.png`});
  };
  try {
    await goto(page,'/hospital-admin/staff');await page.getByRole('button',{name:'Add doctor',exact:true}).click();
    for(const [label,value]of [['First name','Synthetic'],['Last name','E2E Doctor'],['Work email',email],
      ['Temporary password',accounts.password],['Confirm password',accounts.password],['Specialization','Synthetic test'],['Professional license number','SYNTHETIC-'+Date.now()]])
      await fill(page,page.getByRole('textbox',{name:label,exact:true}),value);
    await choose(page,'Department',department.department_name);
    await submit(page,'Create doctor','functions/v1/admin-users');
    const [user]=await rest('hospital_admin','users',`email=eq.${email}`);authId=user.auth_user_id;
    expect(user.account_status).toBe('active');expect(user.hospital_id).toBe(isolation.hospitalId);
    const [doctor]=await rest('hospital_admin','doctors',`user_id=eq.${user.id}`);expect(doctor.department_id).toBe(department.id);
    // The staff list omits search below six rows. Use the protected endpoint's
    // exact ID for status changes, then verify the browser's persisted detail.
    await api('hospital_admin','functions/v1/admin-users',{action:'update_user_status',user_id:user.id,account_status:'suspended'});
    const [persisted]=await rest('super_admin','users',`id=eq.${user.id}&select=id,account_status,hospital_id,role_id`);
    console.log(JSON.stringify({syntheticStaffAfterSuspension:persisted}));
    expect(persisted.account_status).toBe('suspended');
    expect(persisted.hospital_id,'staff remains assigned after Auth status synchronization').toBe(isolation.hospitalId);
    expect(await rest('hospital_admin','users',`id=eq.${user.id}`),'assigned administrator must be able to reactivate suspended staff').toHaveLength(1);
    await verifyBrowserStatus(user.id,'suspended');
    const login=()=>fetch(`${base}/auth/v1/token?grant_type=password`,{method:'POST',
      headers:{apikey:publicKey,'Content-Type':'application/json'},body:JSON.stringify({email,password:accounts.password})});
    expect((await login()).status).toBe(400);
    await api('hospital_admin','functions/v1/admin-users',{action:'update_user_status',user_id:user.id,account_status:'active'});
    await verifyBrowserStatus(user.id,'active');
    expect((await login()).status).toBe(200);
  }finally{
    // Physically remove only the newly-created synthetic account, after checking
    // its exact Auth identity. No clinical records are issued for this actor.
    const [user]=await rest('super_admin','users',`email=eq.${email}`);authId??=user?.auth_user_id;
    if(authId){
      const service=(await management('api-keys')).find(k=>k.name==='service_role')?.api_key;
      const headers={apikey:service,Authorization:`Bearer ${service}`};
      const check=await fetch(`${base}/auth/v1/admin/users/${authId}`,{headers});const owned=await check.json();
      expect(owned.email).toBe(email);expect(email).toMatch(/^repair-e2e-doctor-\d+@example\.test$/);
      const deleted=await fetch(`${base}/auth/v1/admin/users/${authId}`,{method:'DELETE',headers});expect(deleted.status).toBe(200);
      expect(await rest('super_admin','users',`auth_user_id=eq.${authId}`)).toEqual([]);
    }
    await rest('super_admin','hospital_departments',`id=eq.${department.id}`,undefined,'DELETE');
  }
}));
