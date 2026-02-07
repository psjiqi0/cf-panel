// 设置用户名显示
document.getElementById('username_display').textContent = `用户: ${document.body.dataset.username || 'user'}`

// 登出
document.getElementById('btn_logout').onclick = async () => {
  const r = await fetch('/logout', {method:'POST'})
  if (r.ok) { window.location.href = '/login' }
}

// 修改密码
const modal = document.getElementById('modal_change_pass')
const close = document.querySelector('.close')
document.getElementById('btn_change_pass').onclick = () => { modal.style.display = 'block' }
close.onclick = () => { modal.style.display = 'none' }
window.onclick = (e) => { if (e.target === modal) modal.style.display = 'none' }

document.getElementById('btn_save_pass').onclick = async () => {
  const old_pass = document.getElementById('old_pass').value
  const new_pass = document.getElementById('new_pass').value
  const out = document.getElementById('pass_out')
  if (!old_pass || !new_pass) { out.textContent = '请填入密码'; return }
  out.textContent = '保存中...'
  const r = await fetch('/api/change_password', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({old_password:old_pass, new_password:new_pass})})
  const j = await r.json()
  out.textContent = JSON.stringify(j, null, 2)
  if (j.ok) { setTimeout(() => { modal.style.display = 'none'; document.getElementById('old_pass').value = ''; document.getElementById('new_pass').value = '' }, 1000) }
}

// 临时隧道
document.getElementById('btn_temp').onclick = async () => {
  const port = document.getElementById('temp_port').value || '8080'
  const out = document.getElementById('temp_out')
  out.textContent = '启动中...'
  const r = await fetch('/api/temp_tunnel', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({port})})
  const j = await r.json()
  out.textContent = JSON.stringify(j, null, 2)
}

// 加载域名列表
document.getElementById('btn_load_zones').onclick = async () => {
  const token = document.getElementById('token').value
  if (!token) { alert('请输入 API Token'); return }
  const r = await fetch('/api/zones', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({token})})
  const j = await r.json()
  const sel = document.getElementById('zone_select')
  sel.innerHTML = '<option value="">-- 选择域名 --</option>'
  if (!j.ok) {
    alert('加载失败: ' + (j.error || JSON.stringify(j)))
    return
  }
  j.zones.forEach(z => {
    const opt = document.createElement('option')
    opt.value = z.id + '|' + z.name
    opt.textContent = z.name
    sel.appendChild(opt)
  })
}

// 注册并绑定
document.getElementById('btn_register').onclick = async () => {
  const token = document.getElementById('token').value
  const account_id = document.getElementById('account_id').value
  const zone_val = document.getElementById('zone_select').value
  const subdomain = document.getElementById('subdomain').value
  const local_port = document.getElementById('local_port').value
  const type = document.getElementById('service_type').value
  
  if (!zone_val) { alert('请选择域名'); return }
  const [zone_id, domain] = zone_val.split('|')
  
  const out = document.getElementById('register_out')
  out.textContent = '处理中...'
  const r = await fetch('/api/register', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({token, account_id, domain, zone_id, subdomain, local_port, type})})
  const j = await r.json()
  out.textContent = JSON.stringify(j, null, 2)
  if (j.ok) { setTimeout(() => { document.getElementById('btn_list').click() }, 1000) }
}

// 列出已保存的域名
document.getElementById('btn_list').onclick = async () => {
  const d = document.getElementById('list')
  d.textContent = '加载中...'
  const r = await fetch('/api/list')
  const j = await r.json()
  if (!j.ok) { d.textContent = JSON.stringify(j); return }
  d.innerHTML = ''
  j.items.forEach(it => {
    const div = document.createElement('div')
    div.className = 'domain-item'
    div.setAttribute('data-domain', it.domain)
    div.innerHTML = `<b>${it.domain}</b> (port ${it.local_port}) <button class="btn-run">启动</button><button class="btn-delete">删除</button>`
    d.appendChild(div)
  })
}

// 使用事件委托处理删除和启动按钮
document.addEventListener('click', async (e) => {
  // 处理启动按钮
  if (e.target.closest('.btn-run')) {
    const domain = e.target.closest('.domain-item').getAttribute('data-domain')
    const rr = await fetch('/api/run', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({domain})})
    const jj = await rr.json()
    alert(JSON.stringify(jj))
    return
  }
  // 处理删除按钮
  if (e.target.closest('.btn-delete')) {
    const domain = e.target.closest('.domain-item').getAttribute('data-domain')
    if (!confirm(`确定删除 ${domain} 吗？`)) return
    const rr = await fetch('/api/delete', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({domain})})
    const jj = await rr.json()
    alert(JSON.stringify(jj))
    if (jj.ok) { document.getElementById('btn_list').click() }
    return
  }
})

// 启动节点
document.getElementById('btn_node').onclick = async () => {
  const type = document.getElementById('node_type').value
  const domain = document.getElementById('node_domain').value
  const port = document.getElementById('node_port').value
  const path = document.getElementById('node_path').value
  const out = document.getElementById('node_out')
  out.textContent = '启动中...'
  const r = await fetch('/api/start_node', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({type, domain, port, path})})
  const j = await r.json()
  out.textContent = JSON.stringify(j, null, 2)
}

// 初始化：加载列表
document.getElementById('btn_list').click()
