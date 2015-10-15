# coding: utf-8
from __future__ import unicode_literals
import json
import os

from boto3 import Session


class ECSService(object):

    def __init__(self, access_key, secret_key, region='us-east-1'):
        session = Session(aws_access_key_id=access_key, aws_secret_access_key=secret_key, region_name=region)
        self.client = session.client('ecs')

    def describe_cluster(self, cluster):
        """
        Describe the cluster or raise an Exception if cluster does not exists
        :param cluster: the cluster name
        :return: the response or raise an Exception
        """
        response = self.client.describe_clusters(clusters=[cluster])
        failures = response.get('failures')
        if failures:
            raise Exception("Cluster '%s' is %s" % (cluster, failures[0].get('reason')))
        return response

    def describe_service(self, cluster, service):
        """
        Describe the specified service or raise an Exception if service does not exists in cluster
        :param cluster: the cluster name
        :param service: the service name
        :return: the response or raise an Exception
        """
        response = self.client.describe_services(cluster=cluster, services=[service])
        failures = response.get('failures')
        if failures:
            raise Exception("Service '%s' is %s in cluster '%s'" % (service, failures[0].get('reason'), cluster))
        return response

    def register_task_definition(self, file):
        """
        Register the task definition contained in the file
        :param file: the task definition content file
        :return: the response or raise an Exception
        """
        if os.path.isfile(file) is False:
            raise IOError('The task definition file does not exist')

        with open(file, 'r') as content_file:
            task_file = json.loads(content_file.read())

        response = self.client.register_task_definition(family=task_file.get('family'),
                                                        containerDefinitions=task_file.get('containerDefinitions'),
                                                        volumes=task_file.get('volumes'))
        task_definition = response.get('taskDefinition')
        if task_definition.get('status') is 'INACTIVE':
            arn = task_definition.get('taskDefinitionArn')
            raise Exception('Task definition (%s) is inactive' % arn)
        return response

    def downscale_service(self, cluster, service, delta=1):
        """
        Downscale a service
        :param cluster: the cluster name
        :param service: the service name
        :param delta: Number of tasks to shutdown relatively to the running tasks (1 by default)
        :return: the response or raise an Exception
        """
        response = self.describe_service(cluster=cluster, service=service)
        running_count = (response.get('services')[0]).get('runningCount')
        task_definition = (response.get('services')[0]).get('taskDefinition')
        desired_count = running_count - delta
        return self.update_service(cluster=cluster, service=service, taskDefinition=task_definition,
                                   desiredCount=desired_count)

    def upscale_service(self, cluster, service, delta=1):
        """
        Upscale a service
        :param cluster: the cluster name
        :param service: the service name
        :param delta: Number of tasks to start relatively to the running tasks (1 by default)
        :return: the response or raise an Exception
        """
        response = self.describe_service(cluster=cluster, service=service)
        running_count = (response.get('services')[0]).get('runningCount')
        task_definition = (response.get('services')[0]).get('taskDefinition')
        desired_count = running_count + delta
        return self.update_service(cluster=cluster, service=service, taskDefinition=task_definition,
                                   desiredCount=desired_count)

    def update_service(self, cluster, service, taskDefinition, desiredCount=None):
        """
        Update the service with the task definition
        :param cluster: the cluster name
        :param service: the service name
        :param taskDefinition: the task definition
        :param delta: Number of tasks to start/shutdown relatively to the running tasks
        :return: the response or raise an Exception
        """
        if desiredCount is None:
            self.client.update_service(cluster=cluster, service=service, taskDefinition=taskDefinition)
        else:
            self.client.update_service(cluster=cluster, service=service, taskDefinition=taskDefinition,
                                   desiredCount=desiredCount)

        # Waiting for the service update is done
        waiter = self.client.get_waiter('services_stable')
        waiter.wait(cluster=cluster, services=[service])
        return self.describe_service(cluster=cluster, service=service)
