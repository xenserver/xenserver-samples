package testGoSDK

import (
	"fmt"
	"log"
	"strings"
	"time"

	"xenapi"
)

func GetFirstTemplate(templateName string) (xenapi.VMRef, string, error) {
	records, err := xenapi.VM.GetAllRecords(session)
	if err != nil {
		return "", "", err
	}
	// Get the first VM template
	for ref, record := range records {
		if record.IsATemplate && strings.Contains(record.NameLabel, templateName) {
			return ref, record.NameLabel, nil
		}
	}
	return "", "", fmt.Errorf("No VM template found.")
}

func GetStorage() (xenapi.SRRef, error) {
	pools, err := xenapi.Pool.GetAll(session)
	if err != nil {
		return "", err
	}
	defaultSRRef, err := xenapi.Pool.GetDefaultSR(session, pools[0])
	if err != nil {
		return "", err
	}
	if defaultSRRef != "" {
		return defaultSRRef, nil
	}

	srRecords, err := xenapi.SR.GetAllRecords(session)
	if err != nil {
		return "", err
	}
	hostRecords, err := xenapi.Host.GetAllRecords(session)
	if err != nil {
		return "", err
	}
	for srRef, srRecord := range srRecords {
		flag, err := CanCreateVdi(srRecord.Type)
		if err != nil {
			return "", err
		}
		if srRecord.Shared || strings.Compare(srRecord.ContentType, "iso") == 0 || !flag {
			continue
		}
		for _, pbdRef := range srRecord.PBDs {
			attached, err := xenapi.PBD.GetCurrentlyAttached(session, pbdRef)
			if err != nil {
				return "", err
			}
			if !attached {
				continue
			}
			for _, hostRecord := range hostRecords {
				ref, err := xenapi.PBD.GetHost(session, pbdRef)
				if err != nil {
					return "", err
				}
				uuid, err := xenapi.Host.GetUUID(session, ref)
				if err != nil {
					return "", err
				}
				if uuid == hostRecord.UUID {
					return srRef, nil
				}
			}
		}
	}

	return "", fmt.Errorf("No SR found.")
}

func CanCreateVdi(srType string) (bool, error) {
	smRefs, err := xenapi.SM.GetAll(session)
	if err != nil {
		return false, err
	}
	for _, smRef := range smRefs {
		smType, err := xenapi.SM.GetType(session, smRef)
		if err != nil {
			return false, err
		}
		if strings.Compare(smType, srType) == 0 {
			features, err := xenapi.SM.GetFeatures(session, smRef)
			if err != nil {
				return false, err
			}
			_, ok := features["VDI_CREATE"]
			if ok {
				return true, nil
			}
		}
	}
	return false, nil
}

func GetFirstNetwork() (xenapi.NetworkRef, error) {
	networkRefs, err := xenapi.Network.GetAll(session)
	if err != nil {
		return "", err
	}
	if len(networkRefs) == 0 {
		return "", fmt.Errorf("No network found.")
	}
	return networkRefs[0], nil
}

func FindHaltedLinuxVM() (xenapi.VMRef, error) {
	vmRecords, err := xenapi.VM.GetAllRecords(session)
	if err != nil {
		return "", err
	}
	var vmRefTest xenapi.VMRef
	for ref, record := range vmRecords {
		if !record.IsATemplate && !record.IsControlDomain && !strings.Contains(strings.ToLower(record.NameLabel), "windows") && record.PowerState == xenapi.VMPowerStateHalted {
			vmRefTest = ref
			break
		}
	}
	if vmRefTest == "" {
		return "", fmt.Errorf("Cannot find a halted linux VM. Please create one.")
	}
	return vmRefTest, nil
}

func WaitForTask(taskRef xenapi.TaskRef, delay int) error {
	for {
		status, err := xenapi.Task.GetStatus(session, taskRef)
		if err != nil {
			return err
		}
		if status == xenapi.TaskStatusTypePending || status == xenapi.TaskStatusTypeCancelling {
			process, err := xenapi.Task.GetProgress(session, taskRef)
			if err != nil {
				return err
			}
			log.Printf("%.1f%% done", process*100.0)
		}
		if status == xenapi.TaskStatusTypeSuccess || status == xenapi.TaskStatusTypeFailure {
			log.Printf("100%% done")
			return nil
		}
		if status == xenapi.TaskStatusTypeCancelled {
			return fmt.Errorf("Task was cancelled.")
		}

		time.Sleep(time.Duration(delay) * time.Second)
	}
	return nil
}

func WaitForSRReady(session *xenapi.Session, srRefNew xenapi.SRRef) error {
	IsSRCreated := func(event xenapi.EventRecord) bool {
		if event.Class == "pbd"  {
			pbdRecord := event.Snapshot.(map[string]interface{})
			if pbdRecord["SR"].(string) == string(srRefNew) && pbdRecord["currently_attached"].(bool) {
				return true
			}
		}
		return false
	}
	err := WaitUntil(session, []string{"PBD"}, IsSRCreated)
	if err != nil {
		return err
	}
	return nil
}

func WaitUntil(session *xenapi.Session, eventTypes []string, fn func(xenapi.EventRecord) bool) error {
	token := ""
	maxTries := 3
	for i := 0; i < maxTries; i++ {
		eventBatch, err := xenapi.Event.From(session, eventTypes, token, 10.0)
		if err != nil {
			return err
		}
		token = eventBatch.Token
		for _, event := range eventBatch.Events {
			if fn(event) {
				return nil
			}
		}
		time.Sleep(time.Duration(5) * time.Second)
	}
	return fmt.Errorf("Cannot find an expected event.")
}
