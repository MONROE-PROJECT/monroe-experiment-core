#!flask/bin/python

# Author: Jonas Karlsson <jonas.karlsson@kau.se>, Mohammad Rajiullah <mohammad.rajiullah@kau.se>
# Date: April 2019
# License: GNU General Public License v3

from flask import Flask, jsonify, request, abort, Response, send_file, after_this_request
from flask_api import status
from subprocess import check_output, CalledProcessError
from zipfile import ZipFile
from os.path import basename
import re, os, json

_DEBUG = False

_EXPERIMENT_PATH = os.environ.get("USERDIR")
_SYNC_PATH = os.environ.get("USER_RSYNC_TODIR")
_SYNC_REPO = os.environ.get("USER_RSYNC_REPO", "")
_LISTEN_ADDRESS = os.environ.get("TAP_AGENT_LISTEN_ADDRESS", "0.0.0.0")
_TAP_AGENT_PORT = int(os.environ.get("TAP_AGENT_PORT", "8080"))
_SSL_CERT = os.environ.get("TAP_AGENT_CERT")
_SSL_KEY = os.environ.get("TAP_AGENT_KEY")
_API_KEY = os.environ.get("TAP_AGENT_API_KEY", "$3cr3t_Pa$$w0rd!")

#Read errocodes for container-start and container-deploy and reverse order
_ERRORCODE_MAPPPING = {}
for key, value in os.environ.items():
    # Not error proof but this is due to leagcy
    if key.startswith("ERROR_") or key.startswith("NOERROR_"):
        _ERRORCODE_MAPPPING[int(value)] = key

app = Flask(__name__)
# TODO : Check so flask is multithreaded
def set_experiment(action, schedid):
    try:
        cmd=['/usr/bin/container-{}.sh'.format(action),schedid]
        if action == "deploy":
            # Workaround for files with same name on physcial node
            cmd=['/opt/monroe/tap-agent/container-deploy.sh',schedid]
            cmd.append('wait')
        check_output(cmd)
    except CalledProcessError as e:
        error=_ERRORCODE_MAPPPING.get(e.returncode, f"Unknown error {e}")
        abort_with_response(f"Could not {action} experiment {schedid}, {error}",status.HTTP_500_INTERNAL_SERVER_ERROR)

def check_api_key(headers):
    auth = headers.get("X-Api-Key")
    if auth != _API_KEY:
        abort_with_response(f"ERROR Unauthorized",status.HTTP_401_UNAUTHORIZED)
    return True

def get_experiments(only_running = False):
    retur = ""
    try:
        cmd = ['/usr/bin/experiments']
        if not only_running:
            cmd.append('-a')
        retur = check_output(cmd)
    except CalledProcessError as e:
        retur = e.output

    return str(retur, 'utf-8').rstrip().split()

def abort_with_response(message, status):
    error_message = json.dumps({"Message": str(message)})
    abort(Response(error_message, status))

## Deploy ################################################################################
@app.route('/api/v1.0/experiment/<string:schedid>', methods=['POST'])
def deploy_experiment(schedid):
    check_api_key(request.headers)
    # We did not send a json or no script tag
    print(f"Trying to deploy {schedid}")
    if not request.json or not 'script' in request.json:
        abort_with_response(f"No script specified for : {schedid}", status.HTTP_412_PRECONDITION_FAILED)

    # We provided a schedid with wrong fromat
    # TODO: print help message?
    if re.search(r'[^A-Za-z0-9_\-]',schedid):
        abort_with_response(f"Invalid schedid : {schedid}, allowed values [A-z],[0-9],[_,-]", status.HTTP_412_PRECONDITION_FAILED)

    # We have a correct schedid
    # TODO : set schedid in the config file ?
    experiment_config = os.path.normpath(("{}/{}.conf").format(_EXPERIMENT_PATH, schedid))

    # Does the file already (ie is it already deployed)
    if schedid in get_experiments(only_running=False):
        abort_with_response(f"Experiment already exist : {schedid}", status.HTTP_409_CONFLICT)

    # Create the experiment config file
    try:
        with open(experiment_config, "w") as f:
            json.dump(fp=f, obj=request.json)
    except EnvironmentError:
        abort_with_response(f"Could not create configuration file {experiment_config}", status.HTTP_500_INTERNAL_SERVER_ERROR)

    # Yaay we have a config file
    # TODO: read status form container deploy and .status file
    set_experiment("deploy", schedid)

    return jsonify({ "Message": "{} succesfully deployed".format(schedid)}), status.HTTP_201_CREATED

## Start ###############################################################################
@app.route('/api/v1.0/experiment/<string:schedid>', methods=['PUT'])
def start_experiment(schedid):
    check_api_key(request.headers)
    running=get_experiments(only_running=True)
    #Maybe not necessary
    if running:
        abort_with_response(f"Cannot start, experiment(s) is/are running : {running}", status.HTTP_409_CONFLICT)

    if schedid not in get_experiments(only_running=False):
        abort_with_response(f"Experiment not deployed : {schedid}", status.HTTP_412_PRECONDITION_FAILED)

    # Yaay we have a config file and nothing is running
    # TODO: read status .status file
    set_experiment("start", schedid)

    return jsonify({ "Message": "{} succesfully started".format(schedid)}), 201

## Stop ################################################################################
@app.route('/api/v1.0/experiment/<string:schedid>', methods=['DELETE'])
def stop_experiment(schedid):
    check_api_key(request.headers)
    experiment = os.path.normpath(("{}/{}").format(_EXPERIMENT_PATH, schedid))

    # Maybe not necessary
    if schedid not in get_experiments(only_running=False):
        abort_with_response(f"Experiment not deployed : {schedid}", status.HTTP_412_PRECONDITION_FAILED)

    if os.path.isfile("{}.{}".format(experiment,"stopped")):
        abort_with_response(f"Experiment already stopped : {schedid}", status.HTTP_410_GONE)

    # Yaay we have a config file
    # TODO: ?
    set_experiment("stop", schedid)

    return jsonify({ "Message": "{} succesfully stoppped".format(schedid)}), status.HTTP_200_OK

## Get status ###########################################################################
@app.route('/api/v1.0/experiment/<string:schedid>', methods=['GET'])
def get_experiment_status(schedid):
    if schedid in get_experiments(only_running=True):
        return jsonify({ "Message": f"Experiment {schedid} is running"}), status.HTTP_200_OK
    elif schedid in get_experiments(only_running=False):
        return jsonify({ "Message": f"Experiment {schedid} is deployed but not running"}), status.HTTP_428_PRECONDITION_REQUIRED
    else:
        return jsonify({ "Message": f"Experiment {schedid} do not exist"}), status.HTTP_404_NOT_FOUND

## Get status all ########################################################################
@app.route('/api/v1.0/experiment',strict_slashes=False, methods=['GET'])
def get_experiment_status_all():
    # Workaround for files with same name on physcial node
    try:
        cmd='/usr/bin/docker ps | /bin/grep monroe-namespace'
        check_output(cmd, shell=True)
    except CalledProcessError as e:
        abort_with_response("Monroe subsystem(ie namespace) is down", status.HTTP_503_SERVICE_UNAVAILABLE)

    return jsonify({
        "ScheduledExperiments": get_experiments(only_running=False),
        "RunningExperiments": get_experiments(only_running=True)
        })

## Get results############################################################################
@app.route('/api/v1.0/experiment/<string:schedid>/results', strict_slashes=False, methods=['GET'])
def get_experiment_results(schedid):
    check_api_key(request.headers)

    experiment_syncfolder = os.path.normpath(("{}/{}").format(_SYNC_PATH, schedid))
    # TODO : Use temporary directory/filename
    result_zip='/tmp/results_{}.zip'.format(schedid)

    # Sync the experiment results (monroe only allows to sync all experiments)
    # TODO: Save the log ?
    try:
        # Workaround for files with same name on physcial node
        cmd=['/opt/monroe/tape-agent/monroe-sync-experiments']
        check_output(cmd)
    except CalledProcessError as e:
        abort_with_response(f"Sync failed :{e.output}", status.HTTP_500_INTERNAL_SERVER_ERROR)

    if _SYNC_REPO:
        return jsonify({ "Message": f"{schedid} have been synched to : {_SYNC_REPO}:{_SYNC_REPO}"}), status.HTTP_200_OK

    # If we have a local repo we zip everthing up into a file
    # crawling through directory and subdirectories
    with ZipFile(result_zip,'w') as zip:
        for root, directories, files in os.walk(experiment_syncfolder):
            for filename in files:
                # join the two strings in order to form the full filepath.
                file_path=os.path.join(root, filename)
                zip.write(file_path, os.path.relpath(file_path, _SYNC_PATH))

    @after_this_request
    def cleanup(response):
        try:
            os.remove(result_zip)
        except Exception as e:
            print(f"Could not remove {result_zip} due to : {e}")
        return response

    return send_file(result_zip)


## deploy + start ################################################################################
@app.route('/api/v1.0/experiment/<string:schedid>/start', methods=['POST'])
def deploy_start_experiment(schedid):
    deploy_experiment(schedid)
    return start_experiment(schedid)

## stop + get ################################################################################
@app.route('/api/v1.0/experiment/<string:schedid>/stop', methods=['POST'])
def stop_get_experiment(schedid):
    stop_experiment(schedid)
    return get_experiment_results(schedid)


if __name__ == '__main__':
    if _SSL_CERT and _SSL_KEY:
        print(f"Using cert : {_SSL_CERT} with key : {_SSL_KEY}")
        _SSL_CONTEXT=(_SSL_CERT, _SSL_KEY)
    else:
        print("Using ad hoc mode")
        _SSL_CONTEXT='adhoc'

    app.run(ssl_context=_SSL_CONTEXT, host=_LISTEN_ADDRESS, debug=_DEBUG,port=_TAP_AGENT_PORT)
