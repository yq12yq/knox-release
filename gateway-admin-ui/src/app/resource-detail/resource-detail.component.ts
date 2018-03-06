/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import { Component, OnInit, ViewChild } from '@angular/core';
import { ResourceService } from '../resource/resource.service';
import { Resource } from '../resource/resource';
import { ProviderConfig } from './provider-config';
import { Descriptor } from "./descriptor";
import { Service } from "../resource/service";
import { parseString } from 'xml2js';

import 'brace/theme/monokai';
import 'brace/mode/xml';

import { ProviderConfigSelectorComponent } from "../provider-config-selector/provider-config-selector.component";


@Component({
  selector: 'app-resource-detail',
  templateUrl: './resource-detail.component.html',
  styleUrls: ['./resource-detail.component.css']
})
export class ResourceDetailComponent implements OnInit {

  // Static "empty" Resource used for clearing the display between resource selections
  private static emptyResource: Resource = new Resource();

  private static emptyDescriptor: Descriptor = new Descriptor();

  title: string;

  resourceType: string;
  resource: Resource;
  resourceContent: string;

  providers: Array<ProviderConfig>;

  descriptor: Descriptor;

  availableProviderConfigs: Resource[];

  @ViewChild('choosePC')
  chooseProviderConfigModal: ProviderConfigSelectorComponent;

  constructor(private resourceService: ResourceService) {
  }

  ngOnInit() {
      this.resourceService.getResources('Provider Configurations').then(pcs => {
          this.availableProviderConfigs = pcs;
      });

      this.resourceService.selectedResourceType$.subscribe(type => this.setResourceType(type));
      this.resourceService.selectedResource$.subscribe(value => this.setResource(value));
  }

  get self() {
      return this;
  }

  setResourceType(resType: string) {
      if (resType !== this.resourceType) {

        if (resType === 'Descriptors') {
          // Update the available provider configurations if we're dealing with descriptors
          this.resourceService.getResources("Provider Configurations").then(result => this.availableProviderConfigs = result);
        }

        // Clear the current resource details
        if (this.resource) {this.resource.name = '';} // This clears the details title when the type context changes
        this.resource = ResourceDetailComponent.emptyResource;
        this.providers = null;
        this.descriptor = ResourceDetailComponent.emptyDescriptor;
        this.resourceContent = ''; // Clear the content area
        this.resourceType = resType;
      }
  }

  setResource(res: Resource) {
      //console.debug('ResourceDetailComponent --> setResource() --> ' + ((res) ? res.name : 'null'));
      this.referencedProviderConfigError = false;
      this.resource = res;
      this.providers = [];
      this.resourceService.getResource(this.resourceType, res).then(content => this.setResourceContent(res, content));
  }

  setResourceContent(res: Resource, content: string) {
      switch(this.resourceType) {
          case 'Provider Configurations': {
              this.setProviderConfigContent(res, content);
              break;
          }
          case 'Descriptors': {
              this.setDescriptorContent(res, content);
              break;
          }
      }
  }

  setProviderConfigContent(res: Resource, content: string) {
      this.resourceContent = content;
      if (this.resourceContent) {
          try {
            let contentObj;
            if (res.name.endsWith('json')) {
                // Parse the JSON representation
                contentObj = JSON.parse(this.resourceContent);
                this.providers = contentObj['providers'];
            } else if (res.name.endsWith('yaml') || res.name.endsWith('yml')) {
                // Parse the YAML representation
                let yaml = require('js-yaml');
                contentObj = yaml.load(this.resourceContent);
                this.providers = contentObj['providers'];
            } else if (res.name.endsWith('xml')) {
                // Parse the XML representation
                parseString(this.resourceContent, (err, result) => {
                    let tempProviders = new Array<ProviderConfig>();
                    result['gateway'].provider.forEach(entry => {
                       let providerConfig: ProviderConfig = entry;
                       let params = {};
                       entry.param.forEach(param => {
                           params[param.name] = param.value;
                       });
                       providerConfig.params = params;
                       tempProviders.push(providerConfig);
                    });
                    this.providers = tempProviders;
                });
            }
          } catch (e) {
            console.error('Error parsing ' + res.name + ' content: ' + e);
          }
      }
  }

  setDescriptorContent(res: Resource, content: string) {
    this.resourceContent = content;
    if (this.resourceContent) {
      try {
        console.debug('ResourceDetailComponent --> setDescriptorContent() --> Parsing descriptor ' + res.name);
        let contentObj;
        if (res.name.endsWith('json')) {
          contentObj = JSON.parse(this.resourceContent);
        } else if (res.name.endsWith('yaml') || res.name.endsWith('yml')) {
          let yaml = require('js-yaml');
          contentObj = yaml.load(this.resourceContent);
        }
        let tempDesc = new Descriptor();
        if (contentObj) {
          tempDesc.discoveryAddress = contentObj['discovery-address'];
          tempDesc.discoveryUser = contentObj['discovery-user'];
          tempDesc.discoveryPassAlias = contentObj['discovery-pwd-alias'];
          tempDesc.discoveryCluster = contentObj['cluster'];
          tempDesc.providerConfig = contentObj['provider-config-ref'];
          tempDesc.services = contentObj['services'];
        }
        this.descriptor = tempDesc;
      } catch (e) {
        console.error('ResourceDetailComponent.setDescriptorContent: Error parsing '+ res.name + ' content: ' + e);
      }
    }
  }

  persistChanges() {
    switch(this.resourceType) {
        case 'Provider Configurations' : {
            this.persistProviderConfiguration();
            break;
        }
        case 'Descriptors': {
            this.persistDescriptor();
        }
    }
  }

  persistProviderConfiguration() {
    let content;
    let ext = this.resource.name.split('.').pop();
    switch(ext) {
      case 'json': {
        content = this.resourceService.serializeProviderConfiguration(this.providers, 'json');
        break;
      }
      case 'yaml':
      case 'yml': {
        content = this.resourceService.serializeProviderConfiguration(this.providers, 'yaml');
        break;
      }
      case 'xml': {
        // We're not going to bother serializing XML. Rather, delete the original XML resource, and replace it
        // with JSON
        console.debug('Replacing XML provider configuration ' + this.resource.name + ' with JSON...');

        // Generate the JSON representation of the updated provider configuration
        content = this.resourceService.serializeProviderConfiguration(this.providers, 'json');

        let replacementResource = new Resource();
        replacementResource.name = this.resource.name.slice(0, -4) + '.json';
        replacementResource.href = this.resource.href;

        // Delete the XML resource
        this.resourceService.deleteResource(this.resource.href)
          .then(() => {
          // Save the updated content
          this.resourceService.saveResource(replacementResource, content).then(() => {
            // Update the list of provider configuration to ensure that the XML one is replaced with the JSON one
            this.resourceTypesService.selectResourceType(this.resourceType);
            // Update the detail view
            this.resourceService.selectedResource(replacementResource);
          })
          .catch(err => {
              console.error('Error persisting ' + replacementResource.name + ' : ' + err);
          });
        });
        break;
      }
    }
  }


  persistDescriptor() {
    let content;
    let ext = this.resource.name.split('.').pop();
    switch(ext) {
      case 'json': {
        content = this.resourceService.serializeDescriptor(this.descriptor, 'json');
        break;
      }
      case 'yaml':
      case 'yml': {
        content = this.resourceService.serializeDescriptor(this.descriptor, 'yaml');
        break;
      }
    }

    // Save the updated content
    this.resourceService.saveResource(this.resource, content)
      .then(() => {
          // Refresh the presentation
          this.resourceService.selectedResource(this.resource);
      })
      .catch(err => {
          console.error('Error persisting ' + this.resource.name + ' : ' + err);
      });
  }


  discardChanges() {
    this.resourceService.selectedResource(this.resource);
  }


  deleteResource() {
    let resourceName = this.resource.name;
    this.resourceService.deleteResource(this.resource.href)
                        .then(() => {
                            console.debug('Deleted ' + resourceName);
                            // This refreshes the list of resources
                            this.resourceTypesService.selectResourceType(this.resourceType);
                        })
                        .catch((err: HttpErrorResponse) => {
                            if (err.status === 304) { // Not Modified
                                console.log(resourceName + ' cannot be deleted while there are descriptors actively referencing it.');
                                this.referencedProviderConfigError = true;
                            } else {
                                console.error('Error deleting ' + resourceName + ' : ' + err.message)
                            }
                        });
  }


  onRemoveProvider(name: string) {
    //console.debug('ResourceDetailComponent --> onRemoveProvider() --> ' + name);
    for(let i = 0; i < this.providers.length; i++) {
      if(this.providers[i].name === name) {
        this.providers.splice(i, 1);
        break;
      }
    }
    this.changedProviders = this.providers;
  }

  onProviderEnabled(provider: ProviderConfig) {
      provider.enabled = this.isProviderEnabled(provider) ? 'false' : 'true';
      this.changedProviders = this.providers;
  }

  onRemoveProviderParam(pc: ProviderConfig, paramName: string) {
    //console.debug('ResourceDetailComponent --> onRemoveProviderParam() --> ' + pc.name + ' --> ' + paramName);
    if(pc.params.hasOwnProperty(paramName)) {
        delete pc.params[paramName];
    }
    this.changedProviders = this.providers;
  }


  onRemoveDescriptorService(serviceName: string) {
    //console.debug('ResourceDetailComponent --> onRemoveDescriptorService() --> ' + serviceName);
    for(let i = 0; i < this.descriptor.services.length; i++) {
      if(this.descriptor.services[i].name === serviceName) {
        this.descriptor.services.splice(i, 1);
        this.descriptor.setDirty();
        break;
      }
    }
  }


  onRemoveDescriptorServiceParam(serviceName: string, paramName: string) {
    //console.debug('ResourceDetailComponent --> onRemoveDescriptorServiceParam() --> ' + serviceName + ' : ' + paramName);
    let done: boolean = false;
    for(let i = 0; i < this.descriptor.services.length; i++) {
      if(this.descriptor.services[i].name === serviceName) {
        let service = this.descriptor.services[i];
        if(service.params.hasOwnProperty(paramName)) {
          delete service.params[paramName];
          this.descriptor.setDirty();
          done = true;
          break;
        }
      }
      if (done) { // Stop checking services if it has already been handled
        break;
      }
    }
    return result;
  }


  getServiceParamKeys(service: Service): string[] {
    let result = [];
    for(let key in service.params){
      if (service.params.hasOwnProperty(key)){
        result.push(key);
      }
    }
    return result;
  }

  hasSelectedResource(): boolean {
    return Boolean(this.resource) && Boolean(this.resource.name);
  }

  getTitleSubject(): string {
      switch(this.resourceType) {
          case 'Topologies': {
              return 'Topology';
          }
          case 'Provider Configurations':
          case 'Descriptors': {
              return this.resourceType.substring(0, this.resourceType.length - 1);
          }
          default: {
              return 'Resource';
          }
      }
  }

}
