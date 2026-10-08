"""Isolated PostgreSQL/PHP submission regression test; never imports candidate data."""
import base64, concurrent.futures, json, os, re, shutil, subprocess, tempfile, time, urllib.request, urllib.error
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
PG = Path(os.environ.get('HRMS_TEST_PG_BIN', 'C:/Program Files/PostgreSQL/17/bin'))
PHP = shutil.which('php')
FLAGS = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
work = Path(tempfile.mkdtemp(prefix='hrms-submission-'))
server = None
started = False

def run(args, **kwargs):
    # File handles prevent PostgreSQL child processes retaining a capture pipe on Windows.
    with tempfile.TemporaryFile() as output:
        result = subprocess.run([str(x) for x in args], stdout=output, stderr=output, creationflags=FLAGS, **kwargs)
        output.seek(0)
        text = output.read().decode(errors='replace')
    if result.returncode: raise RuntimeError(text)
    return text

def sql(text):
    return run([PG/'psql.exe', '-h', '127.0.0.1', '-p', '55439', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-At', '-c', text])

def request(route, body, content_type):
    req = urllib.request.Request('http://127.0.0.1:55440/api/index.php?route='+route, data=body, headers={'Content-Type':content_type})
    try:
        with urllib.request.urlopen(req, timeout=20) as res:
            return res.status, json.loads(res.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())

def application(key, name='Synthetic Candidate', email='synthetic@example.invalid', omit=None):
    boundary = 'hrms-test-boundary'
    chunks = []
    fields = {'first_name':name.split()[0], 'surname':' '.join(name.split()[1:]), 'email':email, 'phone':'09123456789', 'position':'Staff', 'date_of_birth':'1990-01-01', 'submission_key':key}
    for k,v in fields.items():
        chunks.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=')
    documents = [('id_photo','id.png','image/png',png), ('id_picture','photo.png','image/png',png), ('resume','resume.pdf','application/pdf',b'%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF')]
    documents += [(field, field+'.png', 'image/png', png) for field in ['sss_picture','pag_ibig_picture','nbi_picture','psa_picture']]
    for field, filename, mime, data in documents:
        if field == omit: continue
        chunks.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{field}"; filename="{filename}"\r\nContent-Type: {mime}\r\n\r\n'.encode()+data+b'\r\n')
    chunks.append(f'--{boundary}--\r\n'.encode())
    return request('applicants', b''.join(chunks), 'multipart/form-data; boundary='+boundary)

def receipt(key):
    return request('applicants/receipt', json.dumps({'submission_key':key}).encode(), 'application/json')

try:
    run([PG/'initdb.exe','-D',work/'db','-U','postgres','-A','trust','--no-locale','-E','UTF8'])
    run([PG/'pg_ctl.exe','-D',work/'db','-l',work/'postgres.log','-o','-h 127.0.0.1 -p 55439','-w','start'])
    started = True
    dump = (ROOT/'latest6.sql').read_text()
    for table in ['applicants','employees','users','system_activities']:
        definition = re.search(r'CREATE TABLE public\.'+table+r' \(.*?\n\);',dump,re.S).group()
        definition = definition.replace('id integer NOT NULL', 'id SERIAL PRIMARY KEY',1)
        sql(definition)
    fn = dump[dump.index('CREATE FUNCTION public.enforce_unique_person_name()'):dump.index('ALTER FUNCTION public.enforce_unique_person_name()')]
    sql(fn)
    sql((ROOT/'repair-application-submission.sql').read_text())
    sql((ROOT/'repair-application-submission.sql').read_text())
    print('PASS non-destructive migration and repeat migration')
    site = work/'site'
    (site/'api').mkdir(parents=True)
    for source in (ROOT/'api').glob('*.php'): shutil.copy(source,site/'api'/source.name)
    shutil.copy(ROOT/'router.php', site/'router.php')
    env = dict(os.environ, DB_HOST='127.0.0.1',DB_PORT='55439',DB_NAME='postgres',DB_USER='postgres',DB_PASS='',DB_SSLMODE='disable',APP_ENV='development')
    log = open(work/'php.log','w')
    server = subprocess.Popen([PHP,'-S','127.0.0.1:55440','router.php'],cwd=site,env=env,stdout=log,stderr=log,creationflags=FLAGS)
    time.sleep(1)
    assert receipt('a'*64)==(200,{'received':False})
    for missing in ['id_photo','id_picture','resume','sss_picture','pag_ibig_picture','nbi_picture','psa_picture']:
        status, data = application('9'*64, omit=missing)
        assert status == 400 and 'all required documents' in data['error'], (missing,status,data)
        assert sql('SELECT count(*) FROM applicants').strip() == '0'
        assert not (site/'api/applicant-id-photos').exists()
    print('PASS each missing attachment rejected before database insert or file storage')
    start = time.monotonic()
    status,data = application('a'*64)
    assert status==201 and data['id']>0, (status,data)
    assert time.monotonic()-start<5
    assert receipt('a'*64)==(200,{'received':True})
    assert application('a'*64)[1]['already_submitted'] is True
    assert sql('SELECT count(*) FROM applicants').strip()=='1'
    assert len(list((site/'api/applicant-id-photos').iterdir()))==7
    print('PASS multipart upload, receipt reconciliation, identical retry, one row and seven files')
    status,data = application('b'*64, 'Synthetic Other', 'other@example.invalid')
    assert status==201,(status,data)
    # Separate database connections model concurrent inserts, including the trigger lock.
    insert = "INSERT INTO applicants (name,email,phone,applied_date,submission_key) VALUES ('Concurrent Candidate','concurrent@example.invalid','09123456789','2026-10-08','"+'c'*64+"')"
    def concurrent_insert():
        try: sql(insert); return True
        except RuntimeError: return False
    with concurrent.futures.ThreadPoolExecutor(2) as pool:
        results = list(pool.map(lambda _:concurrent_insert(),range(2)))
    assert sorted(results)==[False,True],results
    assert sql("SELECT count(*) FROM applicants WHERE submission_key='"+'c'*64+"'").strip()=='1'
    print('PASS concurrent duplicate inserts create one row')
    # Holding the historical shared lock must no longer block an unrelated candidate.
    holder = subprocess.Popen([str(PG/'psql.exe'),'-h','127.0.0.1','-p','55439','-U','postgres','-c','BEGIN; SELECT pg_advisory_xact_lock(19789,1); SELECT pg_sleep(6); COMMIT;'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,creationflags=FLAGS)
    time.sleep(.5)
    start=time.monotonic()
    assert application('d'*64,'Independent Candidate','independent@example.invalid')[0]==201
    assert time.monotonic()-start<3
    holder.wait()
    print('PASS unrelated applications no longer wait on historical global lock')
    # Same-name lock remains protective, but requests fail promptly and can retry.
    holder = subprocess.Popen([str(PG/'psql.exe'),'-h','127.0.0.1','-p','55439','-U','postgres','-c',"BEGIN; SELECT pg_advisory_xact_lock(19789,hashtext('blocked candidate')); SELECT pg_sleep(6); COMMIT;"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,creationflags=FLAGS)
    time.sleep(.5)
    files_before = len(list((site/'api/applicant-id-photos').iterdir()))
    start=time.monotonic()
    status,data=application('e'*64,'Blocked Candidate','blocked@example.invalid')
    assert status==503 and 'busy' in data['error'],(status,data)
    assert time.monotonic()-start<5
    assert receipt('e'*64)[1]['received'] is False
    assert len(list((site/'api/applicant-id-photos').iterdir()))==files_before
    holder.wait()
    assert application('e'*64,'Blocked Candidate','blocked@example.invalid')[0]==201
    print('PASS bounded lock failure, upload cleanup, no save, successful same-receipt retry')
    # Lock optional activity logging: receipt/body must reach client without waiting.
    holder = subprocess.Popen([str(PG/'psql.exe'),'-h','127.0.0.1','-p','55439','-U','postgres','-c','BEGIN; LOCK TABLE system_activities IN ACCESS EXCLUSIVE MODE; SELECT pg_sleep(5); COMMIT;'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,creationflags=FLAGS)
    time.sleep(.5)
    start=time.monotonic()
    assert application('f'*64,'Activity Candidate','activity@example.invalid')[0]==201
    assert time.monotonic()-start<1.5
    holder.wait()
    assert receipt('f'*64)[1]['received'] is True
    print('PASS success delivered before blocked optional activity logging')
finally:
    if server:
        server.terminate(); server.wait(); log.close()
    if started: run([PG/'pg_ctl.exe','-D',work/'db','-m','immediate','-w','stop'])
    assert work.resolve().parent == Path(tempfile.gettempdir()).resolve() and work.name.startswith('hrms-submission-')
    shutil.rmtree(work)
