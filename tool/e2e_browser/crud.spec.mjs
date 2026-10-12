import {test,expect,withRole,goto,fill,rest,prefix,isolateHospital,restoreHospital,openSection,search,submit,deleteVisible,choose} from '../e2e_support.mjs';
import {rpc,accounts,fixture} from '../repair_fixture_api.mjs';
import {readFile} from 'node:fs/promises';
import {sql} from '../repair_backend.mjs';
let isolation;
test.beforeAll(async()=>{isolation=await isolateHospital();});
test.afterAll(async()=>{if(isolation)await restoreHospital(isolation);});

for(const resource of [{table:'hospital_beds',tab:'Capacity',kind:'bed',field:'bed_type',total:'total_beds',available:'available_beds'},
  {table:'hospital_rooms',tab:'Rooms',kind:'room',field:'room_type',total:'total_rooms',available:'available_rooms'}]) {
  test(`${resource.table}: browser create, fetch, update, reload and delete`,async()=>withRole('hospital_admin',async page=>{
    const name=prefix+' '+resource.kind;
    await openSection(page,'/hospital-admin/facility',resource.tab);
    await page.getByRole('button',{name:`Add ${resource.kind} type`,exact:true}).click();
    for(const [label,value]of [[`${resource.kind==='bed'?'Bed':'Room'} type`,name],['Total capacity','5'],['Available capacity','4']])await fill(page,page.getByRole('textbox',{name:label,exact:true}),value);
    await submit(page,'Add record',resource.table);
    const [row]=await rest('hospital_admin',resource.table,`${resource.field}=eq.${encodeURIComponent(name)}&hospital_id=eq.${isolation.hospitalId}`);
    console.log(`Fetched ${resource.table} create result`);
    expect(row[resource.total]).toBe(5);expect(row[resource.available]).toBe(4);
    await search(page,name);console.log(`Filtered ${resource.table} to owned record`);await page.getByRole('button',{name:'Edit',exact:true}).click();
    await fill(page,page.getByRole('textbox',{name:/^Total /}),'6');
    await fill(page,page.getByRole('textbox',{name:/^Available /}),'5');
    await submit(page,'Save capacity',resource.table);
    expect((await rest('hospital_admin',resource.table,`id=eq.${row.id}`))[0][resource.total]).toBe(6);
    await openSection(page,'/hospital-admin/facility',resource.tab);await search(page,name);
    await expect(page.getByRole('button',{name:'Edit',exact:true})).toBeVisible();
    await deleteVisible(page,resource.table);
    expect(await rest('hospital_admin',resource.table,`id=eq.${row.id}`)).toEqual([]);
  }));
}
for(const resource of [{table:'hospital_services',tab:'Services',kind:'service',field:'service_name'},
  {table:'hospital_departments',tab:'Departments',kind:'department',field:'department_name'}]) {
  test(`${resource.table}: browser create, fetch, edit, reload and delete`,async()=>withRole('hospital_admin',async page=>{
    const name=prefix+' '+resource.kind;
    await openSection(page,'/hospital-admin/services-departments',resource.tab);
    await page.getByRole('button',{name:`Add ${resource.kind}`,exact:true}).click();
    await fill(page,page.getByRole('textbox',{name:resource.kind==='service'?'Service name':'Department name',exact:true}),name);
    await fill(page,page.getByRole('textbox',{name:/^Description/}), 'Synthetic test only');
    await submit(page,`Add ${resource.kind}`,resource.table);
    const [row]=await rest('hospital_admin',resource.table,`${resource.field}=eq.${encodeURIComponent(name)}&hospital_id=eq.${isolation.hospitalId}`);
    expect(row.hospital_id).toBe(isolation.hospitalId);
    await search(page,name);await page.getByRole('button',{name:'Edit',exact:true}).click();
    await fill(page,page.getByRole('textbox',{name:resource.kind==='service'?'Service name':'Department name',exact:true}),name+' edited');
    await submit(page,'Save changes',resource.table);
    expect((await rest('hospital_admin',resource.table,`id=eq.${row.id}`))[0][resource.field]).toBe(name+' edited');
    await openSection(page,'/hospital-admin/services-departments',resource.tab);await search(page,name+' edited');
    await expect(page.getByRole('button',{name:'View',exact:true})).toBeVisible();
    await deleteVisible(page,resource.table);expect(await rest('hospital_admin',resource.table,`id=eq.${row.id}`)).toEqual([]);
  }));
}

test('facility status: browser CRUD and persisted capacity',async()=>withRole('hospital_admin',async page=>{
  await openSection(page,'/hospital-admin/availability');
  await page.getByRole('button',{name:'Add facility status',exact:true}).click();
  await fill(page,page.getByRole('textbox',{name:'Available units (optional)',exact:true}),'3');
  await fill(page,page.getByRole('textbox',{name:/^Notes/}),prefix);
  await submit(page,'Add facility','hospital_facility_status');
  const [row]=await rest('hospital_admin','hospital_facility_status',`hospital_id=eq.${isolation.hospitalId}`);
  expect(row.available_units).toBe(3);
  await page.getByRole('button',{name:'Edit',exact:true}).click();
  await fill(page,page.getByRole('textbox',{name:'Available units (optional)',exact:true}),'2');
  await submit(page,'Save changes','hospital_facility_status');
  await goto(page,'/hospital-admin/availability');
  expect((await rest('hospital_admin','hospital_facility_status',`id=eq.${row.id}`))[0].available_units).toBe(2);
  await deleteVisible(page,'hospital_facility_status');expect(await rest('hospital_admin','hospital_facility_status',`id=eq.${row.id}`)).toEqual([]);
}));

test('emergency capacity: browser CRUD, computed availability and reload',async()=>withRole('hospital_admin',async page=>{
  await goto(page,'/hospital-admin/emergency-room');
  await page.getByRole('button',{name:'Add ER capacity',exact:true}).click();
  await fill(page,page.getByRole('textbox',{name:'Physical ER beds',exact:true}),'10');
  await fill(page,page.getByRole('textbox',{name:/^Occupied/}),'2');
  await submit(page,'Publish confirmation','emergency_room_status');
  const [row]=await rest('hospital_admin','emergency_room_status',`hospital_id=eq.${isolation.hospitalId}`);
  expect(row.available_beds).toBe(8);
  await page.getByRole('button',{name:'Edit',exact:true}).click();
  await fill(page,page.getByRole('textbox',{name:/^Occupied/}),'3');
  await submit(page,'Publish confirmation','rpc/update_emergency_capacity');
  await goto(page,'/hospital-admin/emergency-room');
  expect((await rest('hospital_admin','emergency_room_status',`id=eq.${row.id}`))[0].available_beds).toBe(7);
  await deleteVisible(page,'emergency_room_status');expect(await rest('hospital_admin','emergency_room_status',`id=eq.${row.id}`)).toEqual([]);
}));

test('hospital: browser create, edit, reload and delete',async()=>withRole('super_admin',async page=>{
  const name=prefix+' managed hospital';let id;
  try {
    await goto(page,'/super-admin/hospitals');await page.getByRole('button',{name:'Add hospital',exact:true}).click();
    for(const [label,value]of [['Hospital name',name],['Address',prefix+' address'],['City','Test City'],['Province','Test Province']])await fill(page,page.getByRole('textbox',{name:label,exact:true}),value);
    await choose(page,'Operating status','Closed');
    await submit(page,'Add hospital','hospitals');
    const [row]=await rest('super_admin','hospitals',`hospital_name=eq.${encodeURIComponent(name)}`);id=row.id;
    expect(row.verification_status).toBe('pending');expect(row.operating_status).toBe('closed');
    await search(page,name);await page.getByRole('button',{name:'Edit',exact:true}).click();
    await fill(page,page.getByRole('textbox',{name:'Hospital name',exact:true}),name+' edited');
    await submit(page,'Save changes','hospitals');
    await goto(page,'/super-admin/hospitals');await search(page,name+' edited');
    expect((await rest('super_admin','hospitals',`id=eq.${id}`))[0].hospital_name).toBe(name+' edited');
    // Reproduce the former HTTP 409: delete the hospital while an audited
    // capacity record still references it, then verify the preserved audit.
    const [bed]=await rest('super_admin','hospital_beds','',{hospital_id:id,bed_type:prefix+' cascade bed',
      total_beds:2,available_beds:2,occupied_beds:0},'POST');
    await deleteVisible(page,'hospitals');expect(await rest('super_admin','hospitals',`id=eq.${id}`)).toEqual([]);
    expect(await rest('super_admin','hospital_beds',`id=eq.${bed.id}`)).toEqual([]);
    const [{count}]=await sql(`select count(*)::int count from public.audit_logs where record_id='${bed.id}' and action='delete'
      and hospital_id is null and metadata->>'source_hospital_id'='${id}'`);
    expect(count).toBe(1);
  }finally{if(id)await rest('super_admin','hospitals',`id=eq.${id}`,undefined,'DELETE');}
}));

test('permission: browser CRUD on an unused synthetic permission',async()=>withRole('super_admin',async page=>{
  const key='synthetic_e2e_'+Date.now();let id;
  try {
    const [role]=await rest('super_admin','roles','role_name=eq.patient&select=id');
    await openSection(page,'/super-admin/system','Permissions');await page.getByRole('button',{name:'Add permission',exact:true}).click();
    await fill(page,page.getByRole('textbox',{name:'Role ID',exact:true}),String(role.id));
    await fill(page,page.getByRole('textbox',{name:'Permission key',exact:true}),key);
    await submit(page,'Add permission','role_permissions');
    const [row]=await rest('super_admin','role_permissions',`permission=eq.${key}`);id=row.id;expect(row.is_allowed).toBe(true);
    await search(page,key);await page.getByRole('button',{name:'Edit',exact:true}).click();
    await page.getByRole('button',{name:'Deny permission',exact:true}).click();
    await submit(page,'Deny permission','role_permissions');
    await openSection(page,'/super-admin/system','Permissions');await search(page,key);
    expect((await rest('super_admin','role_permissions',`id=eq.${id}`))[0].is_allowed).toBe(false);
    await deleteVisible(page,'role_permissions');expect(await rest('super_admin','role_permissions',`id=eq.${id}`)).toEqual([]);
  }finally{if(id)await rest('super_admin','role_permissions',`id=eq.${id}`,undefined,'DELETE');}
}));

test('setting: browser CRUD without changing an existing platform setting',async()=>withRole('super_admin',async page=>{
  const key='synthetic_e2e_'+Date.now();
  try {
    await openSection(page,'/super-admin/system','Settings');await page.getByRole('button',{name:'Add setting',exact:true}).click();
    await fill(page,page.getByRole('textbox',{name:/^Setting key/}),key);
    await fill(page,page.getByRole('textbox',{name:/^Value/}),'original');
    await submit(page,'Add setting','system_settings');
    expect((await rest('super_admin','system_settings',`key=eq.${key}`))[0].value).toBe('original');
    await search(page,key);await page.getByRole('button',{name:'Edit',exact:true}).click();
    await fill(page,page.locator('[role="dialog"], [role="alertdialog"]').getByRole('textbox'),'edited');
    await submit(page,'Save setting','system_settings');
    await openSection(page,'/super-admin/system','Settings');await search(page,key);
    expect((await rest('super_admin','system_settings',`key=eq.${key}`))[0].value).toBe('edited');
    await deleteVisible(page,'system_settings');expect(await rest('super_admin','system_settings',`key=eq.${key}`)).toEqual([]);
  }finally{await rest('super_admin','system_settings',`key=eq.${key}`,undefined,'DELETE');}
}));

test('patient file: real storage upload/download, browser rename/delete and storage cleanup',async()=>withRole('patient',async(page,context)=>{
  const account=accounts.accounts.find(a=>a.role==='patient');
  const [user]=await rest('patient','users',`auth_user_id=eq.${account.id}&select=id`);
  const [patient]=await rest('patient','patients',`user_id=eq.${user.id}&select=id`);
  const title=prefix+' patient document';
  const bytes=await readFile('tool/ui-audit-fixture.pdf');
  // Match the repository path: the second segment identifies the uploader.
  const path=`${patient.id}/${account.id}/${Date.now()}_e2e.pdf`;
  const {base,publicKey,sessions}=await import('../repair_fixture_api.mjs');
  const headers={apikey:publicKey,Authorization:`Bearer ${sessions.patient}`};
  const upload=await fetch(`${base}/storage/v1/object/medical-documents/${path}`,{method:'POST',headers:{...headers,'Content-Type':'application/pdf'},body:bytes});
  expect(upload.status).toBeLessThan(300);
  let id;
  try {
    const [document]=await rest('patient','medical_documents','',{patient_id:patient.id,uploaded_by:user.id,title,document_type:'prescription',storage_bucket:'medical-documents',storage_path:path,mime_type:'application/pdf',size_bytes:bytes.length},'POST');id=document.id;
    expect(document.origin_type).toBe('patient_supplied');
    await goto(page,'/patient/prescriptions');await search(page,title);
    await expect(page.getByRole('button',{name:new RegExp(title)}).first()).toBeVisible();
    const popup=context.waitForEvent('page');await page.getByRole('button',{name:'Download',exact:true}).click();
    const downloadPage=await popup;await downloadPage.waitForURL(/storage\/v1\/object\/sign/);
    const downloaded=await fetch(downloadPage.url());expect(downloaded.status).toBe(200);
    expect(Buffer.from(await downloaded.arrayBuffer()).equals(bytes)).toBe(true);await downloadPage.close();
    await page.getByRole('button',{name:'Edit file title',exact:true}).click();
    await fill(page,page.locator('[role="dialog"], [role="alertdialog"]').getByRole('textbox'),title+' renamed');
    await submit(page,'Save title','rpc/rename_own_medical_document');
    await goto(page,'/patient/prescriptions');await search(page,title+' renamed');
    expect((await rest('patient','medical_documents',`id=eq.${id}`))[0].title).toBe(title+' renamed');
    await page.getByRole('button',{name:'Delete file',exact:true}).click();
    await submit(page,'Delete file','rpc/delete_own_medical_document');
    await expect(page.getByRole('button',{name:'Delete file',exact:true})).toHaveCount(0);
    expect(await rest('patient','medical_documents',`id=eq.${id}`)).toEqual([]);
    await expect.poll(async()=>{
      const [{count}]=await sql(`select count(*)::int count from storage.objects where bucket_id='medical-documents' and name='${path}'`);
      return count;
    }).toBe(0);
  }finally{
    if(id&&(await rest('patient','medical_documents',`id=eq.${id}`)).length)await rpc('patient','delete_own_medical_document',{target_document_id:id});
    await fetch(`${base}/storage/v1/object/medical-documents`,{method:'DELETE',headers:{...headers,'Content-Type':'application/json'},body:JSON.stringify({prefixes:[path]})});
  }
}));

test('maintenance: browser create, edit, deactivate, reload and delete',async()=>withRole('super_admin',async page=>{
  const title=prefix+' maintenance';let id;
  const acceptDateTime=async()=>{
    // Accept the app's future defaults: date then time for start and end.
    for(let i=0;i<3;i++)await page.getByRole('button',{name:'OK',exact:true}).click();
  };
  try {
    await openSection(page,'/super-admin/system','Maintenance');
    await page.getByRole('button',{name:'Schedule maintenance',exact:true}).click();
    await fill(page,page.getByRole('textbox',{name:'Title',exact:true}),title);
    await fill(page,page.getByRole('textbox',{name:/^User-facing message/}),'Synthetic verification notice only.');
    await page.getByRole('button',{name:'Choose schedule',exact:true}).click();await acceptDateTime();
    await submit(page,'OK','maintenance_windows');
    const [row]=await rest('super_admin','maintenance_windows',`title=eq.${encodeURIComponent(title)}`);id=row.id;
    expect(Date.parse(row.ends_at)).toBeGreaterThan(Date.parse(row.starts_at));
    await search(page,title);await page.getByRole('button',{name:'Edit',exact:true}).click();
    await fill(page,page.getByRole('textbox',{name:'Title',exact:true}),title+' edited');
    await page.getByRole('button',{name:'Continue',exact:true}).click();await acceptDateTime();
    await submit(page,'OK','maintenance_windows');
    await search(page,title+' edited');await page.getByRole('button',{name:'Deactivate',exact:true}).click();
    await submit(page,'Deactivate window','maintenance_windows');
    await openSection(page,'/super-admin/system','Maintenance');await search(page,title+' edited');
    const [after]=await rest('super_admin','maintenance_windows',`id=eq.${id}`);expect(after.title).toBe(title+' edited');expect(after.is_active).toBe(false);
    await deleteVisible(page,'maintenance_windows');expect(await rest('super_admin','maintenance_windows',`id=eq.${id}`)).toEqual([]);
  }finally{if(id)await rest('super_admin','maintenance_windows',`id=eq.${id}`,undefined,'DELETE');}
}));

test('doctor schedule: create, fetch, unpublish, reload and delete unused availability',async()=>withRole('doctor',async page=>{
  let id;
  try {
    await goto(page,'/doctor/schedule');await page.getByRole('button',{name:'Add slot',exact:true}).click();
    await fill(page,page.getByRole('textbox',{name:'Starts (24-hour)',exact:true}),'23:40');
    await fill(page,page.getByRole('textbox',{name:'Ends (24-hour)',exact:true}),'23:50');
    await fill(page,page.getByRole('textbox',{name:'Minutes per appointment',exact:true}),'10');
    await submit(page,'Publish slot','doctor_schedules');
    const rows=await rest('doctor','doctor_schedules',`doctor_id=eq.${fixture.id}&starts_at=eq.23:40:00`);
    expect(rows).toHaveLength(1);id=rows[0].id;expect(rows[0].is_active).toBe(true);
    await goto(page,'/doctor/schedule/'+id);
    await page.getByRole('button',{name:'Unpublish',exact:true}).click();
    await submit(page,'Unpublish slot','doctor_schedules');
    await goto(page,'/doctor/schedule/'+id);expect((await rest('doctor','doctor_schedules',`id=eq.${id}`))[0].is_active).toBe(false);
    await page.getByRole('button',{name:'Delete availability',exact:true}).click();
    await submit(page,'Delete availability','doctor_schedules');
    expect(await rest('doctor','doctor_schedules',`id=eq.${id}`)).toEqual([]);
  }finally{if(id)await rest('doctor','doctor_schedules',`id=eq.${id}`,undefined,'DELETE');}
}));
