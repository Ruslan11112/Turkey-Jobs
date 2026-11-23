const client = window.TJ_SUPABASE_URL && window.TJ_SUPABASE_ANON_KEY && window.supabase
  ? window.supabase.createClient(window.TJ_SUPABASE_URL, window.TJ_SUPABASE_ANON_KEY)
  : null;
const byId = (id) => document.getElementById(id);
const showStatus = (id, message, error = false) => {
  const el = byId(id); el.textContent = message; el.classList.toggle('error', error);
};
const portfolioBucket = 'candidate-files';
const maxFileSize = 15 * 1024 * 1024;
const videoBucket = 'candidate-videos';
const maxVideoSize = 50 * 1024 * 1024;
function accountPhone(country,local){const digits=String(local||'').replace(/\D/g,'').replace(/^0+/,'');const prefix=String(country||'').split('-')[0];return digits.length>=6&&digits.length<=13?`${prefix}${digits}`:'';}

async function sendAdminNotification(payload) {
  const { error } = await client.functions.invoke('notify-admin', { body: payload });
  return error;
}

async function loadResume(user) {
  const { data, error } = await client.from('candidate_resumes').select('*').eq('user_id', user.id).maybeSingle();
  if (error) return showStatus('resumeStatus', error.message, true);
  const preview=byId('resumePreview');
  if (!data) { preview.textContent='Заполните резюме, чтобы оно появилось здесь.'; return; }
  const review = byId('resumeReviewStatus');
  review.hidden = !data.review_status;
  review.textContent = ({new:'Резюме ожидает проверки администратора.',reviewing:'Резюме рассматривает администратор.',approved:'Резюме одобрено.',rejected:'Резюме отклонено администратором. Вы можете обновить данные и сохранить его повторно.'})[data.review_status] || '';
  for (const [name, value] of Object.entries(data)) {
    const field = byId('resumeForm').elements.namedItem(name);
    if (field) field.value = value || '';
  }
  renderResumePreview(data);
}

function renderResumePreview(data){const root=byId('resumePreview');root.replaceChildren();[['Должность',data.headline],['О себе',data.summary],['Опыт работы',data.experience],['Образование',data.education],['Навыки',data.skills],['Языки',data.languages]].forEach(([label,value])=>{const section=document.createElement('section');const heading=document.createElement('h3');heading.textContent=label;const text=document.createElement('p');text.textContent=value||'Не указано';section.append(heading,text);root.append(section)})}

async function loadPortfolio(user) {
  const list = byId('portfolioList'); list.replaceChildren();
  const { data, error } = await client.from('portfolio_files').select('id,file_name,storage_path,content_type,size_bytes,created_at').eq('user_id', user.id).order('created_at', { ascending: false });
  if (error) { list.textContent = error.message; return; }
  if (!data.length) { list.textContent = 'Пока нет прикреплённых файлов.'; return; }
  for (const file of data) {
    const item = document.createElement('li');
    const link = document.createElement('a'); link.textContent = `${file.file_name} · ${(file.size_bytes / 1048576).toFixed(1)} МБ`;
    const { data: signed, error: signError } = await client.storage.from(portfolioBucket).createSignedUrl(file.storage_path, 600);
    if (signed?.signedUrl) { link.href = signed.signedUrl; link.target = '_blank'; link.rel = 'noopener'; }
    else { link.href = '#'; link.addEventListener('click', e => { e.preventDefault(); showStatus('portfolioStatus', signError?.message || 'Не удалось открыть файл.', true); }); }
    item.append(link); list.append(item);
  }
}

async function loadVideo(user) {
  const root = byId('myVideo'); root.replaceChildren();
  const { data, error } = await client.from('candidate_videos').select('storage_path,file_name,created_at').eq('user_id', user.id).maybeSingle();
  if (error) { root.textContent = error.message; return; }
  if (!data) { root.textContent = 'Видео пока не загружено.'; return; }
  const { data: signed, error: signError } = await client.storage.from(videoBucket).createSignedUrl(data.storage_path, 600);
  if (!signed?.signedUrl) { root.textContent = signError?.message || 'Видео временно недоступно.'; return; }
  const video = document.createElement('video'); video.controls = true; video.preload = 'metadata'; video.src = signed.signedUrl; video.className = 'candidate-video-preview';
  const label = document.createElement('p'); label.textContent = `Загружено: ${data.file_name} · ${new Date(data.created_at).toLocaleString()}`;
  root.append(video, label);
}

async function loadApplications(user) {
  const list = byId('myApplications');
  const { data, error } = await client.from('applications').select('id,status,created_at,jobs(title,company,city)').eq('user_id', user.id).order('created_at', { ascending: false });
  if (error) { list.textContent = error.message; return; }
  if (!data.length) { list.textContent = 'Вы ещё не отправляли заявки.'; return; }
  list.replaceChildren();
  data.forEach(app => {
    const item = document.createElement('article'); item.className = 'application-row';
    const title = document.createElement('strong'); title.textContent = app.jobs?.title || 'Вакансия';
    const statusLabel=({new:'Новая',reviewing:'На рассмотрении',sent_to_employer:'Передана работодателю',approved:'Одобрена',rejected:'Отклонена'})[app.status]||app.status;
    const meta = document.createElement('span'); meta.textContent = `${app.jobs?.company || ''} · ${app.jobs?.city || ''} · ${statusLabel} · ${new Date(app.created_at).toLocaleDateString()}`;
    item.append(title, meta); list.append(item);
  });
}

async function loadPreferences(user) {
  const {data,error}=await client.from('user_settings').select('vacancy_emails').eq('user_id',user.id).maybeSingle();
  if(error){showStatus('preferencesStatus',error.message,true);return}
  byId('preferencesForm').elements.vacancy_emails.checked=!!data?.vacancy_emails;
}

async function startAccount() {
  if (!client) {
    byId('setupNotice').hidden = false;
    byId('setupNotice').textContent = 'Сначала укажите URL и публичный ключ проекта Supabase в config.js, затем выполните supabase/schema.sql.';
    document.querySelectorAll('.portal-form input,.portal-form textarea,.portal-form button,.preferences-form input,.preferences-form button,.upload-row input,.upload-row button,#editResume,#openPortfolio').forEach(el => el.disabled = true);
    byId('accountIdentity').textContent = 'Профиль пока не подключён к базе данных.';
    return;
  }
  const { data: { session } } = await client.auth.getSession();
  if (!session) {
    byId('setupNotice').hidden = false;
    byId('setupNotice').textContent = 'Личный кабинет кандидата временно отключён. Чтобы подать заявку, вернитесь на главную страницу и нажмите «Оставить заявку».';
    document.querySelectorAll('.portal-form input,.portal-form textarea,.portal-form button,.preferences-form input,.preferences-form button,.upload-row input,.upload-row button,#editResume,#openPortfolio').forEach(el => el.disabled = true);
    byId('accountIdentity').textContent = 'Вход не выполнен.';
    return;
  }
  const accountName=session.user.user_metadata?.full_name||session.user.email?.split('@')[0]||'Пользователь';
  byId('accountIdentity').textContent = session.user.email||session.user.phone||'Аккаунт Turkey Jobs';
  const initials=accountName.trim().split(/\s+/).slice(0,2).map(part=>part[0]?.toLocaleUpperCase('ru')||'').join('');byId('accountAvatar').textContent=initials||'TJ';
  byId('accountAvatar').setAttribute('aria-label',`Аватар пользователя ${accountName}`);
  const metaPhone=session.user.phone||session.user.user_metadata?.phone||'';if(metaPhone.startsWith('+90')){byId('phoneAuthForm').elements.phoneCountry.value='+90';byId('phoneAuthForm').elements.phoneLocal.value=metaPhone.slice(3)}else if(metaPhone.startsWith('+1')){byId('phoneAuthForm').elements.phoneCountry.value='+1';byId('phoneAuthForm').elements.phoneLocal.value=metaPhone.slice(2)}else if(metaPhone.startsWith('+7'))byId('phoneAuthForm').elements.phoneLocal.value=metaPhone.slice(2);
  const { data: isAdmin } = await client.rpc('is_admin_role');
  byId('adminShortcut').hidden = !isAdmin;
  await Promise.all([loadResume(session.user), loadPortfolio(session.user), loadApplications(session.user), loadVideo(session.user), loadPreferences(session.user)]);
}


byId('openPortfolio').addEventListener('click',()=>{if(!confirm('Перед редактированием резюме напомним: после сохранения изменений администратор проверит портфолио и резюме ещё раз. Продолжить?'))return;byId('accountDashboard').hidden=true;byId('portfolioWorkspace').hidden=false;history.replaceState(null,'',`${location.pathname}#portfolio`);window.scrollTo({top:0,behavior:'smooth'})});
byId('backToAccount').addEventListener('click',()=>{byId('portfolioWorkspace').hidden=true;byId('accountDashboard').hidden=false;history.replaceState(null,'',location.pathname);window.scrollTo({top:0,behavior:'smooth'})});
if(location.hash==='#portfolio'&&client)byId('openPortfolio').click();

let pendingPhone='';
byId('phoneAuthForm').addEventListener('submit',async event=>{event.preventDefault();const form=new FormData(event.currentTarget);pendingPhone=accountPhone(form.get('phoneCountry'),form.get('phoneLocal'));if(!pendingPhone)return showStatus('phoneAuthStatus','Введите номер телефона без повторения кода страны.',true);showStatus('phoneAuthStatus','Отправляем код…');const {error}=await client.auth.updateUser({phone:pendingPhone});if(error)return showStatus('phoneAuthStatus',error.message,true);byId('verifyAccountPhone').hidden=false;showStatus('phoneAuthStatus',`Код отправлен на ${pendingPhone}. Введите его на этой странице.`)});
byId('verifyAccountPhone').addEventListener('submit',async event=>{event.preventDefault();const token=new FormData(event.currentTarget).get('code');const {data,error}=await client.auth.verifyOtp({phone:pendingPhone,token,type:'phone_change'});if(error)return showStatus('phoneAuthStatus',error.message,true);if(data.user)await client.from('profiles').update({phone:pendingPhone}).eq('id',data.user.id);showStatus('phoneAuthStatus','Телефон подтверждён. Теперь можно входить по нему и паролю.');byId('verifyAccountPhone').hidden=true;event.currentTarget.reset()});

byId('preferencesForm').addEventListener('submit',async event=>{
  event.preventDefault();showStatus('preferencesStatus','Сохраняем…');
  const {data:{session}}=await client.auth.getSession();
  if(!session)return showStatus('preferencesStatus','Войдите в аккаунт и повторите попытку.',true);
  const {error}=await client.from('user_settings').upsert({user_id:session.user.id,vacancy_emails:byId('preferencesForm').elements.vacancy_emails.checked},{onConflict:'user_id'});
  showStatus('preferencesStatus',error?.message||'Настройки сохранены.');
});

byId('videoForm').addEventListener('submit', async event => {
  event.preventDefault(); showStatus('videoStatus', 'Проверяем и загружаем видео…');
  const file = byId('videoInput').files[0];
  if (!file) return showStatus('videoStatus', 'Выберите видео.', true);
  if (!byId('videoConsent').checked) return showStatus('videoStatus', 'Подтвердите согласие на загрузку видео.', true);
  if (file.size > maxVideoSize) return showStatus('videoStatus', 'Видео должно быть меньше 50 МБ.', true);
  if (!['video/mp4','video/webm'].includes(file.type)) return showStatus('videoStatus', 'Используйте формат MP4 или WebM.', true);
  const duration = await new Promise((resolve, reject) => { const probe = document.createElement('video'); probe.preload='metadata'; probe.onloadedmetadata=()=>{URL.revokeObjectURL(probe.src);resolve(probe.duration)}; probe.onerror=()=>reject(new Error('Не удалось прочитать видео.')); probe.src=URL.createObjectURL(file); });
  if (!Number.isFinite(duration) || duration > 30 || duration <= 0) return showStatus('videoStatus', 'Продолжительность видео должна быть не более 30 секунд.', true);
  const { data: { session } } = await client.auth.getSession();
  if (!session) return showStatus('videoStatus', 'Войдите в аккаунт и повторите попытку.', true);
  const path = `${session.user.id}/${crypto.randomUUID()}-${file.name.replace(/[^\w.\-]+/g,'_')}`;
  const { error: uploadError } = await client.storage.from(videoBucket).upload(path, file, { contentType:file.type, upsert:false });
  if (uploadError) return showStatus('videoStatus', uploadError.message, true);
  const { error } = await client.from('candidate_videos').upsert({ user_id:session.user.id,storage_path:path,file_name:file.name,content_type:file.type,size_bytes:file.size,consented_at:new Date().toISOString() }, { onConflict:'user_id' });
  if (error) { await client.storage.from(videoBucket).remove([path]); return showStatus('videoStatus', error.message, true); }
  await client.from('candidate_resumes').update({review_status:'new'}).eq('user_id',session.user.id);
  byId('videoInput').value=''; byId('videoConsent').checked=false;
  await sendAdminNotification({ resume_user_id: session.user.id });
  showStatus('videoStatus', 'Видео загружено. Администратор получит уведомление.'); await loadVideo(session.user);
});

byId('editResume').addEventListener('click',()=>{const form=byId('resumeForm');form.hidden=!form.hidden;byId('editResume').textContent=form.hidden?'Редактировать резюме':'Скрыть редактор';if(!form.hidden)form.scrollIntoView({behavior:'smooth',block:'center'})});

byId('resumeForm').addEventListener('submit', async event => {
  event.preventDefault(); showStatus('resumeStatus', 'Сохраняем…');
  const { data: { session } } = await client.auth.getSession();
  if (!session) return showStatus('resumeStatus', 'Войдите в аккаунт и повторите попытку.', true);
  const form = new FormData(event.currentTarget);
  const resume = { user_id: session.user.id, headline: form.get('headline').trim(), review_status:'new', summary: form.get('summary').trim(), experience: form.get('experience').trim(), education: form.get('education').trim(), skills: form.get('skills').trim(), languages: form.get('languages').trim() };
  const { error } = await client.from('candidate_resumes').upsert(resume, { onConflict: 'user_id' });
  if (error) return showStatus('resumeStatus', error.message, true);
  await loadResume(session.user);
  const mailError = await sendAdminNotification({ resume_user_id: session.user.id });
  showStatus('resumeStatus', mailError ? 'Изменения сохранены и отправлены на повторную проверку. Уведомление видно администратору в панели.' : 'Изменения сохранены. Администратор проверит резюме повторно.');
});

byId('portfolioForm').addEventListener('submit', async event => {
  event.preventDefault(); showStatus('portfolioStatus', 'Загружаем файл…');
  const file = byId('portfolioInput').files[0];
  if (!file) return showStatus('portfolioStatus', 'Выберите файл.', true);
  if (file.size > maxFileSize) return showStatus('portfolioStatus', 'Размер файла превышает 15 МБ.', true);
  const { data: { session } } = await client.auth.getSession();
  if (!session) return showStatus('portfolioStatus', 'Войдите в аккаунт и повторите попытку.', true);
  const cleanName = file.name.normalize('NFKC').replace(/[^\w.\-]+/g, '_').slice(-160) || 'portfolio-file';
  const path = `${session.user.id}/${crypto.randomUUID()}-${cleanName}`;
  const { error: uploadError } = await client.storage.from(portfolioBucket).upload(path, file, { contentType: file.type || 'application/octet-stream', upsert: false });
  if (uploadError) return showStatus('portfolioStatus', uploadError.message, true);
  const { error: rowError } = await client.from('portfolio_files').insert({ user_id: session.user.id, storage_path: path, file_name: file.name, content_type: file.type, size_bytes: file.size });
  if (rowError) { await client.storage.from(portfolioBucket).remove([path]); return showStatus('portfolioStatus', rowError.message, true); }
  await client.from('candidate_resumes').update({review_status:'new'}).eq('user_id',session.user.id);
  byId('portfolioInput').value = '';
  showStatus('portfolioStatus', 'Файл добавлен в портфолио.'); await loadPortfolio(session.user);
});

byId('complaintForm').addEventListener('submit', async event => {
  event.preventDefault(); showStatus('complaintStatus', 'Отправляем…');
  const { data: { session } } = await client.auth.getSession();
  if (!session) return showStatus('complaintStatus', 'Войдите в аккаунт и повторите попытку.', true);
  const form = new FormData(event.currentTarget);
  const { data, error } = await client.from('complaints').insert({ user_id: session.user.id, subject: form.get('subject').trim(), message: form.get('message').trim() }).select('id').single();
  if (error) return showStatus('complaintStatus', error.message, true);
  const mailError = await sendAdminNotification({ complaint_id: data.id });
  showStatus('complaintStatus', mailError ? 'Сообщение отправлено в панель администратора; email пока не доставлен.' : 'Сообщение отправлено администратору.');
  event.currentTarget.reset();
});

byId('signOut').addEventListener('click', async () => { if (client) await client.auth.signOut(); location.href = 'index.html'; });
startAccount().catch(error => { byId('setupNotice').hidden = false; byId('setupNotice').textContent = error.message || 'Не удалось загрузить личный кабинет.'; });
